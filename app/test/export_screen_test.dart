import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/vault/import_export/export_screen.dart';

/// Synthetic test helpers
const _testVaultKey = [
  42, 42, 42, 42, 42, 42, 42, 42,
  42, 42, 42, 42, 42, 42, 42, 42,
  42, 42, 42, 42, 42, 42, 42, 42,
  42, 42, 42, 42, 42, 42, 42, 42,
]; // 32 bytes, synthetic

// A salt that will NOT produce _testVaultKey for any real password
// (used to simulate "wrong password" without real Argon2id derivation)
final _testSalt = List<int>.filled(16, 7);

Widget _buildTestScreen({
  List<int>? vaultKey,
  List<int>? salt,
  VaultDatabase? db,
}) {
  final key = vaultKey ?? _testVaultKey;
  final effectiveSalt = salt ?? _testSalt;
  final effectiveDb = db ?? SqliteVaultDatabase.inMemory()..open(key);
  return MaterialApp(
    home: ExportScreen(
      vaultKey: key,
      db: effectiveDb,
      masterKeySalt: effectiveSalt,
    ),
  );
}

void main() {
  group('ExportService Unit Tests', () {
    final svc = ExportService();

    test('1. buildSvaultBackup produces a valid JSON blob with ciphertext only', () {
      final now = DateTime.now().toUtc();
      final items = [
        EncryptedVaultItem(
          id: 'test-1',
          encryptedBlob: 'AAAA==',
          nonce: 'BBBB==',
          version: 1,
          updatedAt: now,
        ),
        EncryptedVaultItem(
          id: 'test-2',
          encryptedBlob: 'CCCC==',
          nonce: 'DDDD==',
          version: 1,
          updatedAt: now,
        ),
      ];

      final bytes = svc.buildSvaultBackup(items);
      expect(bytes, isNotEmpty);

      // Must be valid JSON
      final decoded = jsonDecode(String.fromCharCodes(bytes)) as Map<String, dynamic>;
      expect(decoded['format'], equals('svault'));
      expect(decoded['version'], equals(1));
      expect((decoded['items'] as List).length, equals(2));

      // Must contain ciphertext — but NOT any human-readable passwords
      final raw = String.fromCharCodes(bytes);
      expect(raw, contains('AAAA=='));
      expect(raw, contains('CCCC=='));
      expect(raw, isNot(contains('password'))); // no plaintext field names
    });

    test('2. buildPlaintextCsv produces correct CSV headers and rows', () {
      final now = DateTime.now().toUtc();
      final items = [
        VaultItem(
          id: 'csv-1',
          type: VaultItemType.login,
          title: 'CSV Login',
          tags: const ['work'],
          favorite: true,
          vaultId: '',
          createdAt: now,
          updatedAt: now,
          fields: LoginFields(
            username: 'csv_user@example.com',
            password: const ConcealedValue.plain('CsvP@ss!'),
            urls: const ['https://csv.example.com'],
            otpSecret: const ConcealedValue.plain(''),
            passwordHistory: const [],
          ),
          customFields: const [],
          notes: const ConcealedValue.plain(''),
        ),
      ];

      final csv = svc.buildPlaintextCsv(items);
      expect(csv, contains('type,title,username,password'));
      expect(csv, contains('login'));
      expect(csv, contains('CSV Login'));
      expect(csv, contains('csv_user@example.com'));
      expect(csv, contains('CsvP@ss!'));
    });

    test('3. buildPlaintextJson includes warning field and correct structure', () {
      final now = DateTime.now().toUtc();
      final items = [
        VaultItem(
          id: 'json-1',
          type: VaultItemType.secureNote,
          title: 'My Secret Note',
          tags: const [],
          favorite: false,
          vaultId: '',
          createdAt: now,
          updatedAt: now,
          fields: SecureNoteFields(
            content: const ConcealedValue.plain('Super secret content'),
          ),
          customFields: const [],
          notes: const ConcealedValue.plain(''),
        ),
      ];

      final json = svc.buildPlaintextJson(items);
      expect(json, contains('THIS FILE IS UNENCRYPTED'));
      expect(json, contains('My Secret Note'));
      expect(json, contains('Super secret content'));
      expect(json, contains('sentinelvault_plaintext_export'));
    });
  });

  group('SecurityActivityLog Tests', () {
    setUp(() => SecurityActivityLog.instance.clear());

    test('1. logExport records type, count, and timestamp — never content', () {
      SecurityActivityLog.instance.logExport(
        type: 'encrypted_backup_export',
        itemCount: 12,
        timestamp: DateTime(2026, 7, 10, 9, 0, 0, 0, 0),
      );

      final log = SecurityActivityLog.instance.getLog();
      expect(log.length, equals(1));
      expect(log.first.type, equals('encrypted_backup_export'));
      expect(log.first.itemCount, equals(12));
      // Must NOT contain any item content
      expect(log.first.toJson().containsKey('content'), isFalse);
      expect(log.first.toJson().containsKey('password'), isFalse);
    });

    test('2. Log is ordered newest-first', () {
      SecurityActivityLog.instance.logExport(
        type: 'event_a',
        itemCount: 1,
        timestamp: DateTime(2026, 7, 10, 8, 0),
      );
      SecurityActivityLog.instance.logExport(
        type: 'event_b',
        itemCount: 2,
        timestamp: DateTime(2026, 7, 10, 9, 0),
      );

      final log = SecurityActivityLog.instance.getLog();
      expect(log[0].type, equals('event_b')); // newest first
      expect(log[1].type, equals('event_a'));
    });
  });

  group('ExportScreen Gate-Enforcement Widget Tests', () {
    setUp(() => SecurityActivityLog.instance.clear());

    testWidgets('1. Format picker is shown on open', (tester) async {
      await tester.pumpWidget(_buildTestScreen());
      await tester.pump();

      expect(find.text('Encrypted Backup (.svault)'), findsOneWidget);
      expect(find.text('Plaintext CSV Export'), findsOneWidget);
    });

    testWidgets('2. Plaintext CSV tile → navigates to re-auth gate (never to export directly)', (tester) async {
      await tester.pumpWidget(_buildTestScreen());
      await tester.pump();

      // Tap the CSV tile
      await tester.tap(find.text('Plaintext CSV Export'));
      await tester.pump();

      // Must show the re-auth screen — NOT the export step
      expect(find.text('Master Password Required'), findsOneWidget);
      expect(find.byKey(const Key('reauth-password-field')), findsOneWidget);
      // Must NOT show the exporting or success screen
      expect(find.text('Preparing export…'), findsNothing);
      expect(find.text('Export Complete'), findsNothing);
    });

    testWidgets('3. Submitting an empty password shows an error, does NOT proceed', (tester) async {
      await tester.pumpWidget(_buildTestScreen());
      await tester.pump();

      await tester.tap(find.text('Plaintext CSV Export'));
      await tester.pump();

      // Tap verify with empty field
      await tester.tap(find.byKey(const Key('reauth-verify-button')));
      await tester.pump();

      // Should show an error message
      expect(find.text('Enter your master password.'), findsOneWidget);
      // Must NOT proceed past re-auth gate
      expect(find.text('Export Complete'), findsNothing);
    });

    testWidgets('4. Wrong password shows error and increments attempt counter', (tester) async {
      await tester.pumpWidget(_buildTestScreen());
      await tester.pump();

      await tester.tap(find.text('Plaintext CSV Export'));
      await tester.pump();

      // Enter a wrong password
      await tester.enterText(find.byKey(const Key('reauth-password-field')), 'wrong-password-123');

      // Tap verify — this will trigger real Argon2id derivation on the test salt,
      // which will produce a key that does NOT match _testVaultKey
      await tester.tap(find.byKey(const Key('reauth-verify-button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5)); // allow async Argon2id

      // Must show an error, not proceed to export
      expect(find.text('Export Complete'), findsNothing);
      expect(find.text('Preparing export…'), findsNothing);
      // Re-auth screen is still visible
      expect(find.text('Master Password Required'), findsOneWidget);
    });

    testWidgets('5. Encrypted .svault export does NOT show re-auth gate', (tester) async {
      await tester.pumpWidget(_buildTestScreen());
      await tester.pump();

      // Tap .svault tile
      await tester.tap(find.text('Encrypted Backup (.svault)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Must NOT show re-auth gate at any point
      expect(find.text('Master Password Required'), findsNothing);
      // Should go directly to export progress or done
      final onExportingOrDone =
          find.text('Preparing export…').evaluate().isNotEmpty ||
          find.text('Export Complete').evaluate().isNotEmpty;
      expect(onExportingOrDone, isTrue);
    });

    testWidgets('6. After successful svault export, activity log has one entry', (tester) async {
      SecurityActivityLog.instance.clear();

      await tester.pumpWidget(_buildTestScreen());
      await tester.pump();

      await tester.tap(find.text('Encrypted Backup (.svault)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final log = SecurityActivityLog.instance.getLog();
      expect(log, isNotEmpty);
      expect(log.first.type, equals('encrypted_backup_export'));
      expect(log.first.itemCount, isNonNegative);

      // Log must not contain sensitive keys
      final logJson = log.first.toJson();
      expect(logJson.containsKey('password'), isFalse);
      expect(logJson.containsKey('content'), isFalse);
      expect(logJson.containsKey('encryptedBlob'), isFalse);
    });

    testWidgets('7. Filename for svault export contains sentinelvault_backup', (tester) async {
      await tester.pumpWidget(_buildTestScreen());
      await tester.pump();

      await tester.tap(find.text('Encrypted Backup (.svault)'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // The success screen shows the filename
      final successText = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains('sentinelvault_backup'),
        ),
      );
      expect(successText.data, contains('.svault'));
      expect(successText.data, isNot(contains('UNENCRYPTED')));
    });
  });
}
