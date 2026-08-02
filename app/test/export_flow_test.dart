import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/vault/import_export/export_screen.dart';

class FakeNativeCryptoBridge implements NativeCryptoBridge {
  @override
  Future<Uint8List> deriveMasterKey({
    required List<int> password,
    required List<int> salt,
  }) async {
    final input = [...password, ...salt];
    return Uint8List.fromList(List.generate(32, (i) => (input.length + i) % 256));
  }

  @override
  Future<Uint8List> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  }) async {
    return Uint8List.fromList([...plaintext, ...List.filled(16, 0)]);
  }

  @override
  Future<Uint8List> decryptAesGcm({
    required List<int> ciphertextAndMac,
    required List<int> key,
    required List<int> nonce,
  }) async {
    final length = ciphertextAndMac.length - 16;
    return Uint8List.fromList(ciphertextAndMac.sublist(0, length > 0 ? length : 0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  late VaultCrypto crypto;
  late FakeVaultDatabase db;
  late List<int> masterPasswordSalt;
  late List<int> mockVaultKey;
  late ExportService exportService;

  setUp(() async {
    crypto = VaultCrypto(bridge: FakeNativeCryptoBridge());
    db = FakeVaultDatabase();
    masterPasswordSalt = List<int>.generate(16, (i) => i + 1);
    mockVaultKey = await crypto.deriveMasterKey(
      masterPassword: 'CorrectMasterPassword123!',
      salt: masterPasswordSalt,
    );
    exportService = ExportService();
  });

  group('Export Flow & Format Serialization End-to-End Tests', () {
    test('1. Plaintext CSV Export includes all vault item types with correct field values', () async {
      final now = DateTime.now();
      final decryptedItems = <VaultItem>[
        VaultItem(
          id: '1',
          type: VaultItemType.login,
          title: 'GitHub Credentials',
          tags: const [],
          favorite: false,
          vaultId: 'default',
          createdAt: now,
          updatedAt: now,
          customFields: const [],
          fields: LoginFields(
            username: 'octocat',
            password: const ConcealedValue.plain('OctoSecretPass123!'),
            urls: const ['https://github.com'],
            otpSecret: const ConcealedValue.plain(''),
            passwordHistory: const [],
          ),
          notes: const ConcealedValue.plain('My Github Account'),
        ),
        VaultItem(
          id: '2',
          type: VaultItemType.creditCard,
          title: 'Personal Visa Card',
          tags: const [],
          favorite: false,
          vaultId: 'default',
          createdAt: now,
          updatedAt: now,
          customFields: const [],
          fields: CreditCardFields(
            cardholderName: 'Jane Doe',
            cardNumber: const ConcealedValue.plain('4111222233334444'),
            brand: 'Visa',
            expiryMonth: 12,
            expiryYear: 2028,
            cvv: const ConcealedValue.plain('999'),
            pin: const ConcealedValue.plain(''),
          ),
          notes: const ConcealedValue.plain(''),
        ),
        VaultItem(
          id: '3',
          type: VaultItemType.secureNote,
          title: 'Guest Wifi Note',
          tags: const [],
          favorite: false,
          vaultId: 'default',
          createdAt: now,
          updatedAt: now,
          customFields: const [],
          fields: SecureNoteFields(
            content: const ConcealedValue.plain('WPA3Password: SuperWifiKey2026'),
          ),
          notes: const ConcealedValue.plain(''),
        ),
        VaultItem(
          id: '4',
          type: VaultItemType.bankAccount,
          title: 'Chase Checking',
          tags: const [],
          favorite: false,
          vaultId: 'default',
          createdAt: now,
          updatedAt: now,
          customFields: const [],
          fields: BankAccountFields(
            bankName: 'Chase Bank',
            accountType: 'checking',
            accountNumber: const ConcealedValue.plain('9876543210'),
            routingNumber: const ConcealedValue.plain('123456789'),
          ),
          notes: const ConcealedValue.plain(''),
        ),
      ];

      final csvOutput = exportService.buildPlaintextCsv(decryptedItems);

      expect(csvOutput, contains('type,title,username,password,url'));
      expect(csvOutput, contains('login,GitHub Credentials,octocat,OctoSecretPass123!,https://github.com'));
      expect(csvOutput, contains('credit_card,Personal Visa Card,,,,4111222233334444,Visa,12,2028,999,Jane Doe'));
      expect(csvOutput, contains('secure_note,Guest Wifi Note'));
      expect(csvOutput, contains('WPA3Password: SuperWifiKey2026'));
      expect(csvOutput, contains('bank_account,Chase Checking'));
      expect(csvOutput, contains('Chase Bank,9876543210,123456789'));
    });

    test('2. Plaintext JSON Export correctly serializes all item fields', () async {
      final now = DateTime.now();
      final decryptedItems = <VaultItem>[
        VaultItem(
          id: '1',
          type: VaultItemType.login,
          title: 'GitHub Login',
          tags: const [],
          favorite: false,
          vaultId: 'default',
          createdAt: now,
          updatedAt: now,
          customFields: const [],
          fields: LoginFields(
            username: 'dev_user',
            password: const ConcealedValue.plain('JsonSecret123'),
            urls: const [],
            otpSecret: const ConcealedValue.plain(''),
            passwordHistory: const [],
          ),
          notes: const ConcealedValue.plain(''),
        ),
        VaultItem(
          id: '2',
          type: VaultItemType.bankAccount,
          title: 'Savings Account',
          tags: const [],
          favorite: false,
          vaultId: 'default',
          createdAt: now,
          updatedAt: now,
          customFields: const [],
          fields: BankAccountFields(
            bankName: 'Wells Fargo',
            accountType: 'savings',
            accountNumber: const ConcealedValue.plain('1122334455'),
            routingNumber: const ConcealedValue.plain('5544332211'),
          ),
          notes: const ConcealedValue.plain(''),
        ),
      ];

      final jsonOutput = exportService.buildPlaintextJson(decryptedItems);
      final parsed = jsonDecode(jsonOutput) as Map<String, dynamic>;

      expect(parsed['format'], 'sentinelvault_plaintext_export');
      expect(parsed['item_count'], 2);

      final items = parsed['items'] as List<dynamic>;
      expect(items.length, 2);

      final loginItem = items[0] as Map<String, dynamic>;
      expect(loginItem['title'], 'GitHub Login');
      expect(loginItem['fields']['username'], 'dev_user');
      expect(loginItem['fields']['password'], 'JsonSecret123');

      final bankItem = items[1] as Map<String, dynamic>;
      expect(bankItem['title'], 'Savings Account');
      expect(bankItem['fields']['bank_name'], 'Wells Fargo');
      expect(bankItem['fields']['account_number'], '1122334455');
    });

    test('3. Encrypted .svault backup packages ciphertext blobs without decrypting', () async {
      final encItem = EncryptedVaultItem(
        id: 'item_101',
        encryptedBlob: 'dGVzdF9jaXBoZXJ0ZXh0',
        nonce: 'bm9uY2VfMTIz',
        version: 1,
        updatedAt: DateTime.parse('2026-08-01T00:00:00Z'),
      );

      final svaultBytes = exportService.buildSvaultBackup([encItem]);
      final jsonString = utf8.decode(svaultBytes);
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(parsed['format'], 'svault');
      expect(parsed['version'], 1);
      expect(parsed['item_count'], 1);
      expect(parsed['items'][0]['id'], 'item_101');
      expect(parsed['items'][0]['encryptedBlob'], 'dGVzdF9jaXBoZXJ0ZXh0');
    });

    testWidgets('4. Plaintext Export flow requires Master Password re-auth gate and warning modal', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            vaultKey: mockVaultKey,
            db: db,
            masterKeySalt: masterPasswordSalt,
            crypto: crypto,
          ),
        ),
      );

      // Select Plaintext CSV format — directly opens Re-auth step
      await tester.tap(find.text('Plaintext CSV Export'));
      await tester.pumpAndSettle();

      // Verify we are on Re-auth step
      expect(find.text('Master Password Required'), findsOneWidget);

      // Enter WRONG master password
      await tester.enterText(find.byType(TextField), 'WrongPassword!');
      await tester.tap(find.text('Verify & Continue'));
      await tester.pumpAndSettle();

      // Verify error message
      expect(find.textContaining('Incorrect master password'), findsOneWidget);

      // Enter CORRECT master password
      await tester.enterText(find.byType(TextField), 'CorrectMasterPassword123!');
      await tester.tap(find.text('Verify & Continue'));
      await tester.pumpAndSettle();

      // Verify Unencrypted Export Warning modal appears
      expect(find.text('Unencrypted Export Warning'), findsOneWidget);

      // Confirm risk acknowledgement
      await tester.tap(find.text('I understand — export anyway'));
      await tester.pumpAndSettle();

      // Verify Export Complete screen
      expect(find.text('Export Complete'), findsOneWidget);
    });

    testWidgets('5. Encrypted .svault export path bypasses re-auth gate and completes directly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            vaultKey: mockVaultKey,
            db: db,
            masterKeySalt: masterPasswordSalt,
            crypto: crypto,
          ),
        ),
      );

      // Select Encrypted Backup (.svault) — directly executes export
      await tester.tap(find.text('Encrypted Backup (.svault)'));
      await tester.pumpAndSettle();

      // Verify it goes straight to Export Complete without asking for master password
      expect(find.text('Export Complete'), findsOneWidget);
    });
  });
}
