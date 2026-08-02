import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:core/core.dart';
import 'package:app/features/vault/import_export/import_screen.dart';

class FakeFilePicker extends FilePicker {
  final Uint8List fileBytes;
  final String fileName;

  FakeFilePicker({required this.fileBytes, required this.fileName});

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus p1)? onFileLoading,
    bool allowMultiple = false,
    bool withData = true,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    int? compressionQuality,
    bool? allowCompression,
  }) async {
    return FilePickerResult([
      PlatformFile(
        name: fileName,
        size: fileBytes.length,
        bytes: fileBytes,
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNativeCryptoBridge implements NativeCryptoBridge {
  @override
  Future<Uint8List> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  }) async {
    return Uint8List.fromList([...plaintext, ...List.filled(16, 0)]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVaultDatabase implements VaultDatabase {
  final List<EncryptedVaultItem> insertedItems = [];

  @override
  void insertItem(EncryptedVaultItem item) {
    insertedItems.add(item);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sampleVaultKey = List<int>.generate(32, (i) => i);
  final fakeCrypto = VaultCrypto(bridge: FakeNativeCryptoBridge());

  group('Import Screen File Selection to Preview Flow Tests', () {
    testWidgets('1. Bitwarden JSON: Selecting a file goes straight to preview screen', (WidgetTester tester) async {
      const sampleBitwardenJson = '''
{
  "encrypted": false,
  "items": [
    {
      "type": 1,
      "name": "Bitwarden Sample Login",
      "favorite": true,
      "login": {
        "username": "user@bitwarden.com",
        "password": "BitwardenPassword123!",
        "uris": [{"uri": "https://vault.bitwarden.com"}]
      }
    }
  ]
}
''';

      FilePicker.platform = FakeFilePicker(
        fileBytes: Uint8List.fromList(utf8.encode(sampleBitwardenJson)),
        fileName: 'bitwarden-export.json',
      );

      final db = FakeVaultDatabase();

      await tester.pumpWidget(
        MaterialApp(
          home: ImportScreen(
            vaultKey: sampleVaultKey,
            db: db,
            crypto: fakeCrypto,
          ),
        ),
      );

      // Select Bitwarden format
      await tester.tap(find.text('Bitwarden'));
      await tester.pumpAndSettle();

      // Verify we are on Step 1 (file input / paste screen)
      expect(find.text('Select File'), findsOneWidget);

      // Tap Select File
      await tester.tap(find.text('Select File'));
      await tester.pumpAndSettle();

      // Verify we IMMEDIATELY navigated to Preview Screen (Step 2)
      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('ITEMS TO IMPORT'), findsOneWidget);
      expect(find.text('Logins'), findsOneWidget);
    });

    testWidgets('2. Generic CSV: Selecting a file goes straight to preview screen', (WidgetTester tester) async {
      const sampleCsv = '''title,username,password,url,notes
Sample Banking,csv_user@example.com,CsvPass99!,https://mybank.com,Account notes''';

      FilePicker.platform = FakeFilePicker(
        fileBytes: Uint8List.fromList(utf8.encode(sampleCsv)),
        fileName: 'passwords.csv',
      );

      final db = FakeVaultDatabase();

      await tester.pumpWidget(
        MaterialApp(
          home: ImportScreen(
            vaultKey: sampleVaultKey,
            db: db,
            crypto: fakeCrypto,
          ),
        ),
      );

      // Select Generic CSV format by scrolling into view
      final genericCsvFinder = find.text('Generic CSV');
      await tester.scrollUntilVisible(genericCsvFinder, 200);
      await tester.tap(genericCsvFinder);
      await tester.pumpAndSettle();

      // Tap Select File
      await tester.tap(find.text('Select File'));
      await tester.pumpAndSettle();

      // Verify we IMMEDIATELY navigated to Preview Screen (Step 2)
      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('ITEMS TO IMPORT'), findsOneWidget);
      expect(find.text('Logins'), findsOneWidget);
    });

    testWidgets('3. Complete Import from File Preview encrypts and saves items', (WidgetTester tester) async {
      const sampleCsv = '''title,username,password,url,notes
Sample Vault Item,user@vault.io,Pass123!,https://example.com,Notes''';

      FilePicker.platform = FakeFilePicker(
        fileBytes: Uint8List.fromList(utf8.encode(sampleCsv)),
        fileName: 'import_test.csv',
      );

      final db = FakeVaultDatabase();

      await tester.pumpWidget(
        MaterialApp(
          home: ImportScreen(
            vaultKey: sampleVaultKey,
            db: db,
            crypto: fakeCrypto,
          ),
        ),
      );

      final genericCsvFinder = find.text('Generic CSV');
      await tester.scrollUntilVisible(genericCsvFinder, 200);
      await tester.tap(genericCsvFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select File'));
      await tester.pumpAndSettle();

      // Confirm Import on Preview screen
      final confirmBtn = find.byKey(const Key('confirm-import-button'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify Success Screen
      expect(find.text('Import Complete'), findsOneWidget);
      expect(db.insertedItems.length, 1);
    });
  });
}
