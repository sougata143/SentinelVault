/// Synchronisation and replication engine for SentinelVault.
library core.sync;

import 'dart:math';
import '../models/models.dart';
import '../database/vault_database.dart';
import '../auth/vault_lock_manager.dart';

/// Manage sync state, uploads, downloads, and conflict resolution.
class SyncEngine {
  /// Resolves conflicts locally since the server cannot decrypt items.
  ///
  /// Security invariant: Conflict resolution must happen locally.
  /// Uses a last-write-wins mechanism based on the item version and updated timestamp.
  EncryptedVaultItem resolveConflict({
    required EncryptedVaultItem localItem,
    required EncryptedVaultItem remoteItem,
  }) {
    if (remoteItem.version > localItem.version) {
      return remoteItem;
    } else if (localItem.version > remoteItem.version) {
      return localItem;
    }
    return remoteItem.updatedAt.isAfter(localItem.updatedAt) ? remoteItem : localItem;
  }
}

/// The result of a sync push operation.
class SyncPushResult {
  /// Indicates if the push operation was successful.
  final bool success;

  /// The list of items that encountered conflicts on the server.
  final List<EncryptedVaultItem> conflictingItems;

  /// Creates a successful push result.
  SyncPushResult.success() : success = true, conflictingItems = const [];

  /// Creates a conflicted push result with conflicting items from the server.
  SyncPushResult.conflict(this.conflictingItems) : success = false;
}

/// Interface for the remote Sync API client.
abstract class SyncApiClient {
  /// Pulls all encrypted vault items from the remote server.
  Future<List<EncryptedVaultItem>> pull();

  /// Pushes a list of encrypted vault items to the remote server.
  /// 
  /// Returns a [SyncPushResult] representing success or conflicts.
  Future<SyncPushResult> push(List<EncryptedVaultItem> items);
}

/// Manages the offline-first synchronization process on the client.
class VaultSyncManager {
  final VaultDatabase _localDb;
  final SyncApiClient _api;
  final SyncEngine _syncEngine;

  /// Toggle this to simulate network online/offline state.
  bool isOnline;

  /// Creates a new [VaultSyncManager].
  VaultSyncManager({
    required VaultDatabase localDb,
    required SyncApiClient api,
    this.isOnline = true,
  })  : _localDb = localDb,
        _api = api,
        _syncEngine = SyncEngine();

  /// Runs the sync process.
  /// 
  /// 1. If offline, exits immediately (offline-first).
  /// 2. Pulls all remote vault items.
  /// 3. Updates local database with remote items (resolving conflicts if they exist).
  /// 4. Finds all local items that have newer versions than remote and pushes them.
  /// 5. If push returns 409 conflicts, resolves them locally (LWW + version increment) and retries sync.
  Future<void> sync() async {
    if (!isOnline || VaultLockManager.instance.isDuressMode) {
      // Offline-first: CRUD works with no network, sync is skipped until online.
      // Duress mode: sync is bypassed to protect the real vault and hide the decoy state.
      return;
    }

    try {
      // 1. Pull remote items
      final remoteItems = await _api.pull();
      final remoteMap = {for (var item in remoteItems) item.id: item};

      // 2. Process remote updates locally
      for (final remoteItem in remoteItems) {
        final localItem = _localDb.getItem(remoteItem.id);
        if (localItem == null) {
          _localDb.insertItem(remoteItem);
        } else {
          if (localItem.version == remoteItem.version) {
            // If versions are equal, check if contents are different
            if (localItem.encryptedBlob != remoteItem.encryptedBlob ||
                localItem.nonce != remoteItem.nonce ||
                localItem.isDeleted != remoteItem.isDeleted) {
              // Concurrent conflict! Resolve and increment version.
              final resolvedItem = _syncEngine.resolveConflict(
                localItem: localItem,
                remoteItem: remoteItem,
              );
              final finalItem = EncryptedVaultItem(
                id: resolvedItem.id,
                encryptedBlob: resolvedItem.encryptedBlob,
                nonce: resolvedItem.nonce,
                version: localItem.version + 1,
                updatedAt: DateTime.now().toUtc(),
                isDeleted: resolvedItem.isDeleted,
              );
              _localDb.updateItem(finalItem);
            }
          } else if (remoteItem.version > localItem.version) {
            // Remote is newer. Accept remote version.
            _localDb.updateItem(remoteItem);
          }
        }
      }

      // 3. Determine what needs to be pushed
      final localItems = _localDb.getAllItems(includeDeleted: true);
      final List<EncryptedVaultItem> itemsToPush = [];

      for (final localItem in localItems) {
        final remoteItem = remoteMap[localItem.id];
        if (remoteItem == null) {
          // New local item or locally soft-deleted item that remote has never seen
          itemsToPush.add(localItem);
        } else if (localItem.version > remoteItem.version) {
          // Local has newer updates
          itemsToPush.add(localItem);
        }
      }

      if (itemsToPush.isEmpty) {
        // Everything in sync
        return;
      }

      // 4. Push local updates to remote
      final pushResult = await _api.push(itemsToPush);

      if (pushResult.success) {
        // Clean up soft-deleted items locally once they are confirmed on server
        for (final item in itemsToPush) {
          if (item.isDeleted) {
            _localDb.hardDeleteItem(item.id);
          }
        }
      } else {
        // 5. Handle version conflicts (409) client-side
        for (final conflictItem in pushResult.conflictingItems) {
          final localItem = _localDb.getItem(conflictItem.id);
          if (localItem == null) {
            _localDb.insertItem(conflictItem);
          } else {
            // Resolve conflict client-side using last-write-wins
            final resolvedItem = _syncEngine.resolveConflict(
              localItem: localItem,
              remoteItem: conflictItem,
            );

            // Increment version to max(local, remote) + 1 so it beats the server's version
            final finalItem = EncryptedVaultItem(
              id: resolvedItem.id,
              encryptedBlob: resolvedItem.encryptedBlob,
              nonce: resolvedItem.nonce,
              version: max(localItem.version, conflictItem.version) + 1,
              updatedAt: DateTime.now().toUtc(),
              isDeleted: resolvedItem.isDeleted,
            );

            _localDb.updateItem(finalItem);
          }
        }

        // Retry sync to push the resolved items back to the server
        await sync();
      }
    } catch (e) {
      // Network error or other sync exception, fail gracefully
      return;
    }
  }
}

