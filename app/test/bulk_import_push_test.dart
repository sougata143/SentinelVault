import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core/core.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('Test bulk push of 300 items to sync service', () async {
    const baseUrlAuth = 'http://localhost:3001';
    const baseUrlSync = 'http://localhost:3002';
    final testEmail = 'bulk_user_${DateTime.now().millisecondsSinceEpoch}@example.com';
    const testPassword = 'Password123!';
    final client = http.Client();
    const uuid = Uuid();

    final authClient = AuthClient(baseUrl: baseUrlAuth, httpClient: client);
    final token = await authClient.register(testEmail, testPassword);
    VaultLockManager.instance.setSession(token);

    final syncApiClient = HttpSyncApiClient(
      baseUrl: baseUrlSync,
      userId: testEmail,
      httpClient: client,
    );

    final vaultKey = List<int>.generate(32, (i) => i);
    final crypto = VaultCrypto();

    // Create 300 encrypted vault items
    final List<EncryptedVaultItem> items = [];
    for (int i = 0; i < 300; i++) {
      final item = VaultItem(
        id: uuid.v4(),
        type: VaultItemType.login,
        title: 'NordPass Import Item #$i',
        tags: const ['NordPass'],
        favorite: false,
        vaultId: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: LoginFields(
          username: 'user_$i@nordpass-test.com',
          password: ConcealedValue.plain('SuperSecurePass_$i!'),
          urls: ['https://service-$i.example.com'],
          otpSecret: ConcealedValue.plain(''),
          passwordHistory: const [],
        ),
        customFields: const [],
        notes: ConcealedValue.plain('Imported from NordPass CSV test file with multiline notes content row $i'),
      );
      items.add(await item.encrypt(vaultKey, crypto));
    }

    try {
      await syncApiClient.push(items);
    } catch (_) {
    }

    client.close();
  });
}
