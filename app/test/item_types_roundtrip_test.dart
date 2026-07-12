import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/app_shell.dart';
import 'package:app/features/vault/item_detail.dart';
import 'package:core/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Item Types Round-Trip and Link Address Tests', () {
    late VaultDatabase db;
    final vaultKey = List<int>.filled(32, 1);

    setUp(() {
      db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);
    });

    tearDown(() {
      db.close();
    });

    testWidgets('1. Create and Save Identity, Bank Account, Secure Note, and Password', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AppShell(db: db, vaultKey: vaultKey),
      ));

      // 1. Create and save an Identity item
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Identity'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Personal ID'); // Title
      await tester.enterText(find.byType(TextFormField).at(1), 'John'); // First Name
      await tester.enterText(find.byType(TextFormField).at(2), 'Doe'); // Last Name
      await tester.enterText(find.byType(TextFormField).at(5), '123 Tech Lane'); // Street Address

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify the Identity item is added to the database and appears in the list
      expect(find.text('Personal ID'), findsOneWidget);

      // 2. Create and save a Bank Account item
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bank Account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Savings Account'); // Title
      await tester.enterText(find.byType(TextFormField).at(1), 'Apex Bank'); // Bank Name
      await tester.enterText(find.byType(TextFormField).at(2), '9876543210'); // Account Number
      await tester.enterText(find.byType(TextFormField).at(3), '11002233'); // Routing Number

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify Bank Account appeared in list
      expect(find.text('Savings Account'), findsOneWidget);
    });

    testWidgets('2. Create Credit Card with Linked Billing Address (Identity)', (WidgetTester tester) async {
      // Prepopulate an Identity item in database
      final identityItem = VaultItem(
        id: 'id-alice',
        type: VaultItemType.identity,
        title: 'Alice Profile',
        tags: const [],
        favorite: false,
        vaultId: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: IdentityFields(
          firstName: 'Alice',
          lastName: 'Smith',
          birthdate: null,
          gender: null,
          address: IdentityAddress(
            street: '777 Emerald Road',
            city: 'Seattle',
            state: 'WA',
            zip: '98101',
            country: 'US',
          ),
          emails: const [],
          phoneNumbers: const [],
        ),
      );

      final encId = await identityItem.encrypt(vaultKey, VaultCrypto());
      db.insertItem(encId);

      await tester.pumpWidget(MaterialApp(
        home: AppShell(db: db, vaultKey: vaultKey),
      ));

      // Wait for identities list to load
      await tester.pumpAndSettle();

      // Open picker and add Credit Card
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Credit Card'));
      await tester.pumpAndSettle();

      // Fill in credit card fields
      await tester.enterText(find.byType(TextFormField).at(0), 'My Gold Card'); // Title
      await tester.enterText(find.byType(TextFormField).at(1), 'Alice Smith'); // Cardholder Name
      await tester.enterText(find.byKey(const Key('cc-number-field')), '4111222233334444'); // Card Number
      await tester.enterText(find.byType(TextFormField).at(3), '123'); // CVV
      await tester.enterText(find.byType(TextFormField).at(4), '5566'); // PIN

      // Verify dropdown for Billing Address contains the prepopulated Identity item
      final dropdownFinder = find.byKey(const Key('cc-billing-address-dropdown'));
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Select Alice Profile from dropdown list
      await tester.tap(find.text('Alice Profile (Alice Smith)').last);
      await tester.pumpAndSettle();

      // Save the Card
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify the Credit Card item was successfully encrypted, saved, and displays in the list
      expect(find.text('My Gold Card'), findsOneWidget);

      // Verify the saved object in the database has the linked identity ref
      final items = db.getAllItems();
      final ccEnc = items.firstWhere((it) => it.id != 'id-alice');
      final ccDec = await VaultItem.decrypt(ccEnc, vaultKey, VaultCrypto());
      expect(ccDec.fields, isA<CreditCardFields>());
      expect((ccDec.fields as CreditCardFields).billingAddressRef, equals('id-alice'));
    });

    testWidgets('3. Credit Card and Bank Account Number Obscurity in Detail Pane', (WidgetTester tester) async {
      // Mock Clipboard Channel System call
      final List<ClipboardData> clipboardLog = [];
      // ignore: deprecated_member_use
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments as Map);
            clipboardLog.add(ClipboardData(text: args['text'] as String));
            return null;
          }
          return null;
        },
      );

      final ccItem = VaultItem(
        id: 'cc-test-id',
        type: VaultItemType.creditCard,
        title: 'Secret Credit Card',
        tags: const [],
        favorite: false,
        vaultId: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: CreditCardFields(
          cardholderName: 'Bob Builder',
          cardNumber: const ConcealedValue.plain('5555666677778888'),
          brand: 'mastercard',
          expiryMonth: 12,
          expiryYear: 2030,
          cvv: const ConcealedValue.plain('779'),
          pin: const ConcealedValue.plain('1221'),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ItemDetailPane(item: ccItem),
        ),
      ));

      // 1. Card Number should be obscured by default
      expect(find.text('••••••••••••••••'), findsAtLeastNWidgets(1));
      expect(find.text('5555666677778888'), findsNothing);

      // 2. Click CVV visibility off button to reveal CVV (third visible visibility off icon)
      // Icons: 0 is card number, 1 is cvv, 2 is pin
      await tester.tap(find.byIcon(Icons.visibility_off_outlined).at(0));
      await tester.pump();

      // Card number is now revealed
      expect(find.text('5555666677778888'), findsOneWidget);

      // 3. Copy Card Number (Cardholder Name is at index 0, Card Number is at index 1)
      await tester.tap(find.byIcon(Icons.copy_outlined).at(1));
      await tester.pump();

      // Verify copied card number to clipboard
      expect(clipboardLog.last.text, equals('5555666677778888'));
    });
  });
}
