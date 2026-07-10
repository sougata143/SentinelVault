/// Abstract [VaultDatabase] interface shared by all platform implementations.
///
/// Import this file in platform-specific implementations only.
/// Application code should import `vault_database.dart` (the conditional export).
library;

import '../models/models.dart';

/// Abstract interface for locally persisting encrypted vault items.
///
/// Two concrete implementations exist:
/// - [vault_database_io.dart]: SQLite + `package:sqlite3` for native targets.
/// - [vault_database_web.dart]: Pure-Dart Map store for the web target.
abstract class VaultDatabase {
  /// Initialises the database and applies the SQLCipher encryption key.
  ///
  /// [encryptionKey] is the raw AES key bytes.  On web this is a no-op.
  void open(List<int> encryptionKey);

  /// Closes the database and releases all resources.
  void close();

  /// Inserts a new [item]. Throws if an item with the same id already exists.
  void insertItem(EncryptedVaultItem item);

  /// Updates an existing [item] in place.
  void updateItem(EncryptedVaultItem item);

  /// Soft-deletes the item with [id]: sets `isDeleted = true` and increments
  /// the version number for sync compatibility.
  void softDeleteItem(String id);

  /// Hard-deletes [id] from storage. Used by the sync layer for cleanup only.
  void hardDeleteItem(String id);

  /// Returns the item with [id], or `null` if not found.
  EncryptedVaultItem? getItem(String id);

  /// Returns all non-deleted vault items.
  ///
  /// Set [includeDeleted] to `true` to include soft-deleted items
  /// (required by the sync layer).
  List<EncryptedVaultItem> getAllItems({bool includeDeleted = false});

  /// Purges all records (used at logout and in tests).
  void clear();
}
