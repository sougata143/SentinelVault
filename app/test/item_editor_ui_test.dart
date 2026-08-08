import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/vault/item_editor.dart';

class FakeVaultDatabase implements VaultDatabase {
  final List<EncryptedVaultItem> items = [];

  @override
  List<EncryptedVaultItem> getAllItems({bool includeDeleted = false}) {
    return items;
  }

  @override
  void insertItem(EncryptedVaultItem item) {
    items.add(item);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final mockVaultKey = List<int>.generate(32, (i) => i);
  final db = FakeVaultDatabase();

  group('ItemEditorScreen Modern 1Password-Style UI & Visual Grouping Tests', () {
    testWidgets('1. Type Picker renders all 6 category grid tiles', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ItemEditorScreen(
            vaultKey: mockVaultKey,
            db: db,
            onSave: (_) {},
          ),
        ),
      );

      expect(find.text('Select Item Type'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Credit Card'), findsOneWidget);
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Secure Note'), findsOneWidget);
      expect(find.text('Bank Account'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('2. Login Form section card headers, controls, and primary action button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ItemEditorScreen(
            vaultKey: mockVaultKey,
            db: db,
            onSave: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Verify Visible Section Card Headers & Controls
      expect(find.text('ITEM DETAILS'), findsOneWidget);
      expect(find.text('CREDENTIALS'), findsOneWidget);
      expect(find.byKey(const Key('password-field')), findsOneWidget);
      expect(find.byKey(const Key('generate-button')), findsOneWidget);

      // Scroll down to reveal remaining sections
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('WEBSITE URLS'), findsOneWidget);
      expect(find.text('ONE-TIME PASSWORD (TOTP)'), findsOneWidget);

      // Scroll until the Save button is visible (form length varies by viewport)
      await tester.scrollUntilVisible(
        find.text('Save Vault Item'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('ORGANIZATION & NOTES'), findsOneWidget);
      expect(find.text('Save Vault Item'), findsOneWidget);
    });

    testWidgets('3. Credit Card Form section card headers and billing link dropdown', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ItemEditorScreen(
            vaultKey: mockVaultKey,
            db: db,
            onSave: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Credit Card'));
      await tester.pumpAndSettle();

      expect(find.text('CARD DETAILS'), findsOneWidget);
      expect(find.byKey(const Key('cc-number-field')), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('BILLING LINK'), findsOneWidget);
      expect(find.byKey(const Key('cc-billing-address-dropdown')), findsOneWidget);
    });

    testWidgets('4. Bank Account Form section card headers and fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ItemEditorScreen(
            vaultKey: mockVaultKey,
            db: db,
            onSave: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Bank Account'));
      await tester.pumpAndSettle();

      expect(find.text('BANK & ACCOUNT DETAILS'), findsOneWidget);
      expect(find.text('Bank Name'), findsOneWidget);
      expect(find.text('Account Number'), findsOneWidget);
      expect(find.text('Routing Number'), findsOneWidget);
    });

    testWidgets('5. Identity Form section card headers and personal profile fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ItemEditorScreen(
            vaultKey: mockVaultKey,
            db: db,
            onSave: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Identity'));
      await tester.pumpAndSettle();

      expect(find.text('PERSONAL PROFILE'), findsOneWidget);
      expect(find.text('First Name'), findsOneWidget);
      expect(find.text('Last Name'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('ADDRESS'), findsOneWidget);
    });

    testWidgets('6. Secure Note Form section card header and content input', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ItemEditorScreen(
            vaultKey: mockVaultKey,
            db: db,
            onSave: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Secure Note'));
      await tester.pumpAndSettle();

      expect(find.text('SECURE NOTE CONTENT'), findsOneWidget);
      expect(find.text('Secure Content'), findsOneWidget);
    });
  });
}
