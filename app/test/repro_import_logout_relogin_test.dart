@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core/core.dart';
import 'package:uuid/uuid.dart';
import 'package:app/features/vault/import_export/import_screen.dart';

void main() {
  test('Exact Repro Pass: UUID v4 for all items through Logout and Relogin', () async {
    const baseUrlAuth = 'http://localhost:3001';
    const baseUrlSync = 'http://localhost:3002';
    final testEmail = 'repro_user_${DateTime.now().millisecondsSinceEpoch}@example.com';
    const testPassword = 'Password123!';
    final client = http.Client();
    const uuid = Uuid();

    // Step 1: Register and login user
    final authClient = AuthClient(baseUrl: baseUrlAuth, httpClient: client);
    final token = await authClient.register(testEmail, testPassword);
    VaultLockManager.instance.setSession(token);

    // Step 2: Initialize Session 1 (first login)
    final vaultKey = List<int>.generate(32, (i) => i);
    var db1 = SqliteVaultDatabase.inMemory();
    db1.open(vaultKey);

    final syncApiClient = HttpSyncApiClient(
      baseUrl: baseUrlSync,
      userId: testEmail,
      httpClient: client,
    );

    VaultSyncManager.initialize(
      localDb: db1,
      api: syncApiClient,
    );

    // Add 1 manual item (simulating ItemEditorScreen with UUID v4)
    final crypto = VaultCrypto();
    final manualVaultItem = VaultItem(
      id: uuid.v4(),
      type: VaultItemType.login,
      title: 'Manual Item 1',
      tags: const [],
      favorite: false,
      vaultId: '',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      fields: LoginFields(
        username: 'manual@example.com',
        password: ConcealedValue.plain('ManualPass123!'),
        urls: const ['https://manual.example.com'],
        otpSecret: ConcealedValue.plain(''),
        passwordHistory: const [],
      ),
      customFields: const [],
      notes: ConcealedValue.plain(''),
    );
    final encryptedManual = await manualVaultItem.encrypt(vaultKey, crypto);
    db1.insertItem(encryptedManual);

    await VaultSyncManager.instance.sync();
    await syncApiClient.pull();

    // Step 3: Import items (simulating ImportScreen _confirmAndImport with encryptAndSave)
    final importedParsedItem1 = ParsedItem(
      title: 'Imported Login 1',
      type: 'login',
      username: 'imported1@example.com',
      password: 'ImportedPass1!',
      urls: ['https://imported1.example.com'],
    );
    final importedParsedItem2 = ParsedItem(
      title: 'Imported Card 2',
      type: 'credit_card',
      cardholderName: 'Jane Import',
      cardNumber: '4111111111111111',
    );

    await encryptAndSave(importedParsedItem1, vaultKey, db1, crypto);
    await encryptAndSave(importedParsedItem2, vaultKey, db1, crypto);

    await VaultSyncManager.instance.sync();
    await syncApiClient.pull();

    // Step 4: Simulate Logout / App Lock
    VaultSyncManager.clear();
    VaultLockManager.instance.lock();

    // Step 5: Simulate Relogin / Unlock (Session 2)
    VaultLockManager.instance.setSession(token);
    var db2 = SqliteVaultDatabase.inMemory();
    db2.open(vaultKey);

    VaultSyncManager.initialize(
      localDb: db2,
      api: HttpSyncApiClient(
        baseUrl: baseUrlSync,
        userId: testEmail,
        httpClient: client,
      ),
    );

    // Initial sync pull on unlock
    await VaultSyncManager.instance.sync();

    client.close();
  });
}
