import 'package:test/test.dart';
import 'package:core/core.dart';

class MockSyncApiClient implements SyncApiClient {
  final Map<String, EncryptedVaultItem> serverStore = {};
  int pullCount = 0;
  int pushCount = 0;

  @override
  Future<List<EncryptedVaultItem>> pull() async {
    pullCount++;
    return serverStore.values.map((item) {
      // Return a copy to avoid shared mutable state in tests
      return EncryptedVaultItem(
        id: item.id,
        encryptedBlob: item.encryptedBlob,
        nonce: item.nonce,
        version: item.version,
        updatedAt: item.updatedAt,
        isDeleted: item.isDeleted,
      );
    }).toList();
  }

  @override
  Future<SyncPushResult> push(List<EncryptedVaultItem> items) async {
    pushCount++;
    final conflicts = <EncryptedVaultItem>[];

    for (final item in items) {
      final existing = serverStore[item.id];
      if (existing != null) {
        if (item.version < existing.version) {
          conflicts.add(existing);
        } else if (item.version == existing.version) {
          if (item.encryptedBlob != existing.encryptedBlob ||
              item.nonce != existing.nonce ||
              item.isDeleted != existing.isDeleted) {
            conflicts.add(existing);
          }
        }
      }
    }

    if (conflicts.isNotEmpty) {
      return SyncPushResult.conflict(conflicts);
    }

    for (final item in items) {
      serverStore[item.id] = EncryptedVaultItem(
        id: item.id,
        encryptedBlob: item.encryptedBlob,
        nonce: item.nonce,
        version: item.version,
        updatedAt: item.updatedAt,
        isDeleted: item.isDeleted,
      );
    }

    return SyncPushResult.success();
  }
}

void main() {
  group('Offline-First Vault CRUD and Sync Tests', () {
    late SqliteVaultDatabase localDb;
    late MockSyncApiClient api;
    late VaultSyncManager syncManager;

    setUp(() {
      localDb = SqliteVaultDatabase.inMemory();
      localDb.open([]); // Open in-memory without key for testing
      api = MockSyncApiClient();
      syncManager = VaultSyncManager(localDb: localDb, api: api);
    });

    tearDown(() {
      localDb.close();
    });

    test('1. Local CRUD works completely offline', () async {
      syncManager.isOnline = false; // Simulate offline

      final now = DateTime.now().toUtc();
      final item = EncryptedVaultItem(
        id: 'test-item-1',
        encryptedBlob: 'encrypted_username_and_password',
        nonce: 'randomnonce12',
        version: 1,
        updatedAt: now,
      );

      // Create
      localDb.insertItem(item);
      var retrieved = localDb.getItem(item.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(item.id));
      expect(retrieved.encryptedBlob, equals(item.encryptedBlob));
      expect(retrieved.version, equals(1));
      expect(retrieved.isDeleted, isFalse);

      // Edit (Update)
      final editedItem = EncryptedVaultItem(
        id: item.id,
        encryptedBlob: 'updated_encrypted_blob',
        nonce: item.nonce,
        version: 2,
        updatedAt: now.add(const Duration(seconds: 10)),
      );
      localDb.updateItem(editedItem);
      retrieved = localDb.getItem(item.id);
      expect(retrieved!.encryptedBlob, equals('updated_encrypted_blob'));
      expect(retrieved.version, equals(2));

      // Soft delete
      localDb.softDeleteItem(item.id);
      retrieved = localDb.getItem(item.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.isDeleted, isTrue);
      expect(retrieved.version, equals(3)); // Soft delete increments version

      // Active list shouldn't return soft deleted items
      final activeList = localDb.getAllItems(includeDeleted: false);
      expect(activeList.length, equals(0));

      // Full list should return soft deleted items
      final fullList = localDb.getAllItems(includeDeleted: true);
      expect(fullList.length, equals(1));
      expect(fullList[0].id, equals(item.id));

      // Server should not have received any calls because we are offline
      await syncManager.sync();
      expect(api.pullCount, equals(0));
      expect(api.pushCount, equals(0));
    });

    test('2. Sync after reconnecting pushes local changes to server', () async {
      syncManager.isOnline = false; // Start offline

      // Create item offline
      final item = EncryptedVaultItem(
        id: 'offline-item',
        encryptedBlob: 'secret',
        nonce: 'nonce1234567',
        version: 1,
        updatedAt: DateTime.now().toUtc(),
      );
      localDb.insertItem(item);

      // Verify server is empty
      expect(api.serverStore.isEmpty, isTrue);

      // Reconnect and sync
      syncManager.isOnline = true;
      await syncManager.sync();

      // Verify sync pushed to server
      expect(api.pullCount, equals(1));
      expect(api.pushCount, equals(1));
      expect(api.serverStore.containsKey(item.id), isTrue);
      expect(api.serverStore[item.id]!.version, equals(1));
      expect(api.serverStore[item.id]!.encryptedBlob, equals('secret'));
    });

    test('3. Conflict resolution: Last-Write-Wins and version incrementing', () async {
      // 1. Initial State: Item exists on server with version 1
      final now = DateTime.now().toUtc();
      final originalItem = EncryptedVaultItem(
        id: 'conflicted-item-id',
        encryptedBlob: 'original_ciphertext',
        nonce: 'nonce_original',
        version: 1,
        updatedAt: now,
      );
      api.serverStore[originalItem.id] = originalItem;
      localDb.insertItem(originalItem);

      // 2. Both devices go offline
      // Device A (this device) edits the item
      final editTimeA = now.add(const Duration(seconds: 10));
      final editedItemA = EncryptedVaultItem(
        id: originalItem.id,
        encryptedBlob: 'device_a_ciphertext',
        nonce: originalItem.nonce,
        version: 2,
        updatedAt: editTimeA,
      );
      localDb.updateItem(editedItemA);

      // Device B edits the same item in parallel (simulated on server)
      final editTimeB = now.add(const Duration(seconds: 20)); // Device B is newer
      final editedItemB = EncryptedVaultItem(
        id: originalItem.id,
        encryptedBlob: 'device_b_ciphertext',
        nonce: originalItem.nonce,
        version: 2,
        updatedAt: editTimeB,
      );
      api.serverStore[originalItem.id] = editedItemB; // Device B pushed to server first

      // 3. Device A goes online and syncs
      syncManager.isOnline = true;
      await syncManager.sync();

      // Verification:
      // Device A's push had version 2. Server had version 2 with different content ('device_b_ciphertext').
      // Server returned 409 Conflict.
      // Device A client received conflict, resolved locally.
      // Resolution strategy: LWW. Since Device B's updatedAt (20s) > Device A's (10s), B wins.
      // Version must be incremented to max(local.version, remote.version) + 1 = 3.
      // Device A then pushed the resolved version 3 to the server.
      
      final serverItem = api.serverStore[originalItem.id];
      expect(serverItem, isNotNull);
      expect(serverItem!.version, equals(3));
      expect(serverItem.encryptedBlob, equals('device_b_ciphertext')); // B won

      final localItem = localDb.getItem(originalItem.id);
      expect(localItem, isNotNull);
      expect(localItem!.version, equals(3));
      expect(localItem.encryptedBlob, equals('device_b_ciphertext'));
    });

    test('4. Conflict resolution: Local wins when local is newer', () async {
      // 1. Initial State
      final now = DateTime.now().toUtc();
      final originalItem = EncryptedVaultItem(
        id: 'conflicted-item-id-2',
        encryptedBlob: 'original_ciphertext',
        nonce: 'nonce_original',
        version: 1,
        updatedAt: now,
      );
      api.serverStore[originalItem.id] = originalItem;
      localDb.insertItem(originalItem);

      // 2. Both devices go offline
      // Device A (this device) edits the item (newer edit)
      final editTimeA = now.add(const Duration(seconds: 30)); // Device A is newer
      final editedItemA = EncryptedVaultItem(
        id: originalItem.id,
        encryptedBlob: 'device_a_ciphertext',
        nonce: originalItem.nonce,
        version: 2,
        updatedAt: editTimeA,
      );
      localDb.updateItem(editedItemA);

      // Device B edits the same item (older edit)
      final editTimeB = now.add(const Duration(seconds: 15)); // Device B is older
      final editedItemB = EncryptedVaultItem(
        id: originalItem.id,
        encryptedBlob: 'device_b_ciphertext',
        nonce: originalItem.nonce,
        version: 2,
        updatedAt: editTimeB,
      );
      api.serverStore[originalItem.id] = editedItemB; // Device B pushed to server first

      // 3. Device A goes online and syncs
      syncManager.isOnline = true;
      await syncManager.sync();

      // Verification:
      // Device A's push had version 2. Server had version 2 ('device_b_ciphertext').
      // Conflict resolved locally. Device A (A's timestamp > B's timestamp) wins.
      // Version incremented to 3.
      // Server and Local should both have Device A's content with version 3.
      
      final serverItem = api.serverStore[originalItem.id];
      expect(serverItem, isNotNull);
      expect(serverItem!.version, equals(3));
      expect(serverItem.encryptedBlob, equals('device_a_ciphertext')); // A won

      final localItem = localDb.getItem(originalItem.id);
      expect(localItem, isNotNull);
      expect(localItem!.version, equals(3));
      expect(localItem.encryptedBlob, equals('device_a_ciphertext'));
    });

    test('5. Adding a login item and calling sync() results in a real push call with the encrypted blob', () async {
      final now = DateTime.now().toUtc();

      // Simulate a login item that was encrypted and inserted locally.
      // The blob is opaque to the sync layer — sync just pushes ciphertext.
      final loginItem = EncryptedVaultItem(
        id: 'login-item-push-test',
        encryptedBlob: 'aes256gcm:encrypted:login:alice@example.com',
        nonce: 'nonce_login_push_001',
        version: 1,
        updatedAt: now,
      );

      // Insert locally (e.g. after ItemEditor saves)
      localDb.insertItem(loginItem);

      // Server is empty at this point
      expect(api.serverStore.isEmpty, isTrue);
      expect(api.pushCount, equals(0));

      // Trigger sync (simulates what VaultSyncManager.instance.sync() does after insertItem)
      syncManager.isOnline = true;
      await syncManager.sync();

      // Verify the encrypted blob reached the server
      expect(api.pushCount, equals(1));
      expect(api.pullCount, equals(1));
      expect(api.serverStore.containsKey(loginItem.id), isTrue);
      final pushed = api.serverStore[loginItem.id]!;
      expect(pushed.encryptedBlob, equals(loginItem.encryptedBlob));
      expect(pushed.nonce, equals(loginItem.nonce));
      expect(pushed.version, equals(1));
      // Status should be success after a clean push
      expect(VaultSyncManager.currentStatus, equals(SyncStatus.success));
    });

    test('6. Item added on a second simulated device appears after sync on the first', () async {
      final now = DateTime.now().toUtc();

      // Set up a second (simulated) device: same API server, separate local DB
      final device2Db = SqliteVaultDatabase.inMemory();
      device2Db.open([]);
      final device2SyncManager = VaultSyncManager(localDb: device2Db, api: api);

      // Device 2 adds a new item offline, then syncs to server
      final remoteItem = EncryptedVaultItem(
        id: 'device2-only-item',
        encryptedBlob: 'aes256gcm:encrypted:from_device_2',
        nonce: 'nonce_device2_xyz',
        version: 1,
        updatedAt: now,
      );
      device2Db.insertItem(remoteItem);
      device2SyncManager.isOnline = true;
      await device2SyncManager.sync();

      // Confirm server has device 2's item
      expect(api.serverStore.containsKey(remoteItem.id), isTrue);

      // Device 1 (syncManager) has never seen this item locally
      expect(localDb.getItem(remoteItem.id), isNull);

      // Device 1 syncs — should pull device 2's item from the server
      syncManager.isOnline = true;
      await syncManager.sync();

      // Verify device 2's item is now in device 1's local DB
      final pulled = localDb.getItem(remoteItem.id);
      expect(pulled, isNotNull);
      expect(pulled!.encryptedBlob, equals(remoteItem.encryptedBlob));
      expect(pulled.nonce, equals(remoteItem.nonce));
      expect(pulled.version, equals(1));
      expect(VaultSyncManager.currentStatus, equals(SyncStatus.success));

      device2Db.close();
    });
  });
}
