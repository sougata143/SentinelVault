import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/vault/vault_tab.dart';

// ---------------------------------------------------------------------------
// Helper: Creates an EncryptedVaultItem using the Phase 4 legacy migration
// format ("encrypted:title:username:password") that VaultItem.decrypt()
// parses without performing any AES-GCM decryption. This avoids depending
// on a native crypto bridge in widget tests.
// ---------------------------------------------------------------------------
EncryptedVaultItem _legacyItem({
  required String id,
  required String title,
  String username = 'testuser',
  String password = 'TestPass123!',
}) {
  return EncryptedVaultItem(
    id: id,
    encryptedBlob: 'encrypted:$title:$username:$password',
    nonce: 'dGVzdG5vbmNl', // base64("testnonce") — never used in legacy path
    version: 1,
    updatedAt: DateTime(2026, 8, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SqliteVaultDatabase db;
  final vaultKey = List<int>.filled(32, 0x42);

  setUp(() {
    db = SqliteVaultDatabase.inMemory();
    db.open(vaultKey);
  });

  tearDown(() {
    db.close();
  });

  group('Multi-Item Select and Delete Widget Tests', () {
    testWidgets(
      '1. Selecting 3 items and deleting soft-deletes exactly those 3 items',
      (WidgetTester tester) async {
        // Insert 5 test items using the legacy migration format so no real crypto is needed
        db.insertItem(_legacyItem(id: 'item-1', title: 'Item 1 Alpha'));
        db.insertItem(_legacyItem(id: 'item-2', title: 'Item 2 Beta'));
        db.insertItem(_legacyItem(id: 'item-3', title: 'Item 3 Gamma'));
        db.insertItem(_legacyItem(id: 'item-4', title: 'Item 4 Delta'));
        db.insertItem(_legacyItem(id: 'item-5', title: 'Item 5 Epsilon'));

        await tester.pumpWidget(
          MaterialApp(
            home: VaultTab(
              db: db,
              vaultKey: vaultKey,
              currentEmail: 'testuser@sentinelvault.io',
            ),
          ),
        );

        // Let _loadItems() and setState finish
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Verify all 5 items initially rendered
        expect(find.text('Item 1 Alpha'), findsOneWidget);
        expect(find.text('Item 2 Beta'), findsOneWidget);
        expect(find.text('Item 3 Gamma'), findsOneWidget);
        expect(find.text('Item 4 Delta'), findsOneWidget);
        expect(find.text('Item 5 Epsilon'), findsOneWidget);

        // Toggle selection mode via the checklist icon button
        await tester.tap(find.byKey(const Key('toggle-selection-mode-button')));
        await tester.pump();

        // Selection action bar should now be visible showing "0 Selected"
        expect(find.text('0 Selected'), findsOneWidget);

        // Select item-1, item-3, item-4 by tapping their checkboxes
        await tester.tap(find.byKey(const Key('select-item-checkbox-item-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('select-item-checkbox-item-3')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('select-item-checkbox-item-4')));
        await tester.pump();

        // Action header must show "3 Selected"
        expect(find.text('3 Selected'), findsOneWidget);

        // Tap Delete Selected button (trash icon in action bar)
        await tester.tap(find.byKey(const Key('delete-selected-button')));
        await tester.pump();

        // Confirmation dialog must appear
        expect(find.byKey(const Key('confirm-delete-selected-dialog')), findsOneWidget);
        expect(find.text('Delete 3 Items?'), findsOneWidget);

        // Confirm deletion
        await tester.tap(find.byKey(const Key('confirm-delete-selected-button')));
        await tester.pumpAndSettle();

        // Verify database state: item-1, item-3, item-4 must be soft-deleted
        final allDbItems = db.getAllItems(includeDeleted: true);
        final item1Db = allDbItems.firstWhere((it) => it.id == 'item-1');
        final item2Db = allDbItems.firstWhere((it) => it.id == 'item-2');
        final item3Db = allDbItems.firstWhere((it) => it.id == 'item-3');
        final item4Db = allDbItems.firstWhere((it) => it.id == 'item-4');
        final item5Db = allDbItems.firstWhere((it) => it.id == 'item-5');

        expect(item1Db.isDeleted, isTrue,  reason: 'item-1 (selected) must be soft-deleted');
        expect(item3Db.isDeleted, isTrue,  reason: 'item-3 (selected) must be soft-deleted');
        expect(item4Db.isDeleted, isTrue,  reason: 'item-4 (selected) must be soft-deleted');

        expect(item2Db.isDeleted, isFalse, reason: 'item-2 (not selected) must NOT be soft-deleted');
        expect(item5Db.isDeleted, isFalse, reason: 'item-5 (not selected) must NOT be soft-deleted');
      },
    );

    testWidgets(
      '2. Delete All prompts for confirmation, cancellation is a no-op, then confirm soft-deletes every item',
      (WidgetTester tester) async {
        db.insertItem(_legacyItem(id: 'item-a', title: 'Vault Item A'));
        db.insertItem(_legacyItem(id: 'item-b', title: 'Vault Item B'));
        db.insertItem(_legacyItem(id: 'item-c', title: 'Vault Item C'));

        await tester.pumpWidget(
          MaterialApp(
            home: VaultTab(
              db: db,
              vaultKey: vaultKey,
              currentEmail: 'testuser@sentinelvault.io',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Toggle selection mode to show the action bar with Delete All button
        await tester.tap(find.byKey(const Key('toggle-selection-mode-button')));
        await tester.pump();

        // Tap Delete All button (trash-forever icon in action bar)
        await tester.tap(find.byKey(const Key('delete-all-button')));
        await tester.pump();

        // Confirmation dialog MUST appear before executing — safety guard
        expect(find.byKey(const Key('confirm-delete-all-dialog')), findsOneWidget);
        expect(find.text('Delete All Vault Items?'), findsOneWidget);

        // 2a: Cancel — no items should be deleted
        await tester.tap(find.byKey(const Key('cancel-delete-all-button')));
        await tester.pump();

        expect(find.byKey(const Key('confirm-delete-all-dialog')), findsNothing);
        final itemsAfterCancel = db.getAllItems(includeDeleted: true);
        expect(
          itemsAfterCancel.every((it) => !it.isDeleted),
          isTrue,
          reason: 'No items should be deleted after cancelling the confirmation dialog',
        );

        // 2b: Open dialog again and confirm this time
        await tester.tap(find.byKey(const Key('delete-all-button')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('confirm-delete-all-button')));
        await tester.pumpAndSettle();

        // Every item in vault must now be soft-deleted
        final itemsAfterDelete = db.getAllItems(includeDeleted: true);
        expect(
          itemsAfterDelete.every((it) => it.isDeleted),
          isTrue,
          reason: 'Every vault item must be soft-deleted after confirming Delete All',
        );

        // Main list view should show the empty state text (selection mode exited)
        expect(find.text('No matching items'), findsOneWidget);
      },
    );
  });
}
