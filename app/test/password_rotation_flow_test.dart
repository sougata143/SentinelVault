import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/security_center/password_rotation_dialog.dart';

class FakeVaultDatabase implements VaultDatabase {
  final Map<String, EncryptedVaultItem> _items = {};

  @override
  void open(List<int> encryptionKey) {}

  @override
  void close() {}

  @override
  void insertItem(EncryptedVaultItem item) {
    _items[item.id] = item;
  }

  @override
  void updateItem(EncryptedVaultItem item) {
    _items[item.id] = item;
  }

  @override
  void softDeleteItem(String id) {}

  @override
  void hardDeleteItem(String id) {
    _items.remove(id);
  }

  @override
  EncryptedVaultItem? getItem(String id) => _items[id];

  @override
  List<EncryptedVaultItem> getAllItems({bool includeDeleted = false}) => _items.values.toList();

  @override
  void clear() => _items.clear();
}

void main() {
  testWidgets('PasswordRotationDialog executes rotation flow and rollback safely', (widgetTester) async {
    final crypto = VaultCrypto();
    final key = crypto.generateRandomBytes(32);

    final initialLogin = LoginFields(
      username: 'user@test.com',
      password: const ConcealedValue.plain('OldSecret123!'),
      urls: ['https://example.com/login'],
      otpSecret: const ConcealedValue.plain(''),
      passwordHistory: [],
    );

    final initialItem = VaultItem(
      id: 'item-100',
      type: VaultItemType.login,
      title: 'Example Account',
      tags: [],
      favorite: false,
      vaultId: 'vault-1',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      fields: initialLogin,
      customFields: [],
      notes: const ConcealedValue.plain(''),
    );

    final encInitial = await initialItem.encrypt(key, crypto);
    final db = FakeVaultDatabase();
    db.insertItem(encInitial);

    bool launchedUrl = false;
    VaultItem? rotatedResult;

    await widgetTester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordRotationDialog(
            item: initialItem,
            vaultKey: key,
            db: db,
            urlLauncherOverride: (url) {
              launchedUrl = true;
            },
            onRotated: (item) {
              rotatedResult = item;
            },
          ),
        ),
      ),
    );

    await widgetTester.pumpAndSettle();

    // Verify UI components rendered
    expect(find.text('Rotate Password: Example Account'), findsOneWidget);
    expect(find.byKey(const Key('launch-website-btn')), findsOneWidget);
    expect(find.byKey(const Key('generated-password-display')), findsOneWidget);

    // Launch website button
    await widgetTester.tap(find.byKey(const Key('launch-website-btn')));
    expect(launchedUrl, isTrue);

    // Confirm checkbox
    final checkbox = find.byKey(const Key('confirm-site-change-checkbox'));
    expect(checkbox, findsOneWidget);
    await widgetTester.tap(checkbox);
    await widgetTester.pumpAndSettle();

    // Tap Save & Rotate
    final saveBtn = find.byKey(const Key('confirm-rotate-save-btn'));
    await widgetTester.tap(saveBtn);
    await widgetTester.pumpAndSettle();

    // Rotation completed
    expect(find.text('Password Rotated Successfully!'), findsOneWidget);
    expect(rotatedResult, isNotNull);
    final rotatedLogin = rotatedResult!.fields as LoginFields;
    expect(rotatedLogin.passwordHistory.length, equals(1));
    expect(rotatedLogin.passwordHistory.first.password.plaintext, equals('OldSecret123!'));

    // Tap Undo / Rollback
    final rollbackBtn = find.byKey(const Key('rollback-rotation-btn'));
    expect(rollbackBtn, findsOneWidget);
    await widgetTester.tap(rollbackBtn);
    await widgetTester.pumpAndSettle();

    expect(rotatedResult, isNotNull);
    final rolledBackLogin = rotatedResult!.fields as LoginFields;
    expect(rolledBackLogin.password.plaintext, equals('OldSecret123!'));
    expect(rolledBackLogin.passwordHistory.length, equals(0));
  });
}
