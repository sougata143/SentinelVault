import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/vault/sharing/pqc_sharing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PqcSharingService & Shared Items Persistence', () {
    setUp(() {
      PqcSharingService.unwrappedFolderKeys.clear();
    });

    test('1. unwrappedFolderKeys stores and retrieves folder keys correctly', () {
      final folderId = '55a654ae-9df4-497c-af1b-bb2b7a1aea8e';
      final folderKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

      PqcSharingService.unwrappedFolderKeys[folderId] = folderKey;
      expect(PqcSharingService.unwrappedFolderKeys.containsKey(folderId), isTrue);
      expect(PqcSharingService.unwrappedFolderKeys[folderId], equals(folderKey));
    });

    test('2. Decrypting item encrypted with shared folder key using unwrapped keys', () async {
      final folderId = getFolderUuid('shared-test-folder');
      final masterKey = List<int>.generate(32, (i) => i * 3);
      final folderKey = deriveFolderKey(masterKey, folderId);

      PqcSharingService.unwrappedFolderKeys[folderId] = Uint8List.fromList(folderKey);

      final crypto = VaultCrypto();
      final originalItem = VaultItem(
        id: 'shared-note-1',
        type: VaultItemType.secureNote,
        title: 'Secret Shared Note',
        tags: const ['shared'],
        favorite: false,
        vaultId: folderId,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: SecureNoteFields(
          content: ConcealedValue.plain('Top Secret Payload'),
        ),
        customFields: const [],
        notes: ConcealedValue.plain('Folder note'),
      );

      final encItem = await originalItem.encrypt(folderKey, crypto);
      expect(encItem.folderId, equals(folderId));

      // Simulate recipient decrypting item using unwrapped folder key
      final recipientFolderKey = PqcSharingService.unwrappedFolderKeys[encItem.folderId!];
      expect(recipientFolderKey, isNotNull);

      final decryptedItem = await VaultItem.decrypt(encItem, recipientFolderKey!, crypto);
      expect(decryptedItem.title, equals('Secret Shared Note'));
      final fields = decryptedItem.fields as SecureNoteFields;
      expect(fields.content.plaintext, equals('Top Secret Payload'));
    });
  });
}
