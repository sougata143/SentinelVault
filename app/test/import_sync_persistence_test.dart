@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core/core.dart';
import 'package:app/features/vault/import_export/import_screen.dart';

void main() {
  test('Verify import items persist locally and sync to Postgres backend', () async {
    const baseUrlAuth = 'http://localhost:3001';
    const baseUrlSync = 'http://localhost:3002';
    final testEmail = 'import_test_${DateTime.now().millisecondsSinceEpoch}@example.com';
    const testPassword = 'Password123!';

    // 1. Authenticate / Register test user via AuthClient (SRP-6a)
    final client = http.Client();
    final authClient = AuthClient(baseUrl: baseUrlAuth, httpClient: client);
    final token = await authClient.register(testEmail, testPassword);

    expect(token, isNotEmpty, reason: 'Registration must return session JWT');

    // Set session in VaultLockManager
    VaultLockManager.instance.setSession(token);

    // 2. Initialize local SQLite DB and VaultSyncManager
    final vaultKey = List<int>.generate(32, (i) => i);
    final db = SqliteVaultDatabase.inMemory();
    db.open(vaultKey);

    VaultSyncManager.initialize(
      localDb: db,
      api: HttpSyncApiClient(
        baseUrl: baseUrlSync,
        userId: testEmail,
        httpClient: client,
      ),
    );

    // 3. Encrypt and save 2 sample parsed items (simulating ImportScreen _confirmAndImport)
    final crypto = VaultCrypto();
    final item1 = ParsedItem(
      title: 'Imported Login 1',
      type: 'login',
      username: 'user1@example.com',
      password: 'Pass123!User1',
      urls: ['https://user1.example.com'],
      notes: 'Imported note 1',
    );
    final item2 = ParsedItem(
      title: 'Imported Secure Note 2',
      type: 'secure_note',
      noteContent: 'Imported note content 2',
    );

    await encryptAndSave(item1, vaultKey, db, crypto);
    await encryptAndSave(item2, vaultKey, db, crypto);

    expect(db.getAllItems().length, equals(2), reason: 'Items must exist in local DB');

    // 4. Trigger sync
    await VaultSyncManager.instance.sync();
    expect(VaultSyncManager.currentStatus, equals(SyncStatus.success));

    client.close();
  });
}
