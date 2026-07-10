import 'package:sqlite3/sqlite3.dart';
import '../models/models.dart';
import 'vault_database_interface.dart';

/// SQLite-backed implementation of [VaultDatabase] for native platforms
/// (Android, iOS, macOS, Linux, Windows).
///
/// Uses `package:sqlite3` which relies on `dart:ffi` — not available on web.
/// The web build selects [vault_database_web.dart] instead via conditional
/// export in [vault_database.dart].
class SqliteVaultDatabase implements VaultDatabase {
  final String _dbPath;
  final bool _isInMemory;
  Database? _db;

  /// Creates a file-based SQLite database at [dbPath].
  SqliteVaultDatabase(this._dbPath) : _isInMemory = false;

  /// Creates an in-memory SQLite database (for testing and demos).
  SqliteVaultDatabase.inMemory()
      : _dbPath = '',
        _isInMemory = true;

  /// Returns the active [Database] connection.
  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('Database is not initialized. Call open() first.');
    }
    return database;
  }

  @override
  void open(List<int> encryptionKey) {
    if (_db != null) return;

    _db = _isInMemory ? sqlite3.openInMemory() : sqlite3.open(_dbPath);

    // Set encryption key for SQLCipher-compatible stores.
    // If running against standard SQLite (e.g. standard tests), this is a no-op.
    if (encryptionKey.isNotEmpty) {
      final keyHex =
          encryptionKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA key = \"x'$keyHex'\";");
    }

    _createTables();
  }

  @override
  void close() {
    _db?.dispose();
    _db = null;
  }

  void _createTables() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS vault_items (
        id TEXT PRIMARY KEY,
        encrypted_blob TEXT NOT NULL,
        nonce TEXT NOT NULL,
        version INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  @override
  void insertItem(EncryptedVaultItem item) {
    final stmt = db.prepare('''
      INSERT INTO vault_items (id, encrypted_blob, nonce, version, updated_at, is_deleted)
      VALUES (?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        item.id,
        item.encryptedBlob,
        item.nonce,
        item.version,
        item.updatedAt.toIso8601String(),
        item.isDeleted ? 1 : 0,
      ]);
    } finally {
      stmt.dispose();
    }
  }

  @override
  void updateItem(EncryptedVaultItem item) {
    final stmt = db.prepare('''
      UPDATE vault_items
      SET encrypted_blob = ?, nonce = ?, version = ?, updated_at = ?, is_deleted = ?
      WHERE id = ?
    ''');
    try {
      stmt.execute([
        item.encryptedBlob,
        item.nonce,
        item.version,
        item.updatedAt.toIso8601String(),
        item.isDeleted ? 1 : 0,
        item.id,
      ]);
    } finally {
      stmt.dispose();
    }
  }

  @override
  void softDeleteItem(String id) {
    final item = getItem(id);
    if (item == null || item.isDeleted) return;
    updateItem(
      EncryptedVaultItem(
        id: item.id,
        encryptedBlob: item.encryptedBlob,
        nonce: item.nonce,
        version: item.version + 1,
        updatedAt: DateTime.now().toUtc(),
        isDeleted: true,
      ),
    );
  }

  @override
  void hardDeleteItem(String id) {
    final stmt = db.prepare('DELETE FROM vault_items WHERE id = ?');
    try {
      stmt.execute([id]);
    } finally {
      stmt.dispose();
    }
  }

  @override
  EncryptedVaultItem? getItem(String id) {
    final stmt = db.prepare(
      'SELECT id, encrypted_blob, nonce, version, updated_at, is_deleted '
      'FROM vault_items WHERE id = ?',
    );
    try {
      final results = stmt.select([id]);
      if (results.isEmpty) return null;
      final row = results.first;
      return EncryptedVaultItem(
        id: row['id'] as String,
        encryptedBlob: row['encrypted_blob'] as String,
        nonce: row['nonce'] as String,
        version: row['version'] as int,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDeleted: (row['is_deleted'] as int) == 1,
      );
    } finally {
      stmt.dispose();
    }
  }

  @override
  List<EncryptedVaultItem> getAllItems({bool includeDeleted = false}) {
    final query = includeDeleted
        ? 'SELECT id, encrypted_blob, nonce, version, updated_at, is_deleted FROM vault_items'
        : 'SELECT id, encrypted_blob, nonce, version, updated_at, is_deleted '
            'FROM vault_items WHERE is_deleted = 0';
    return db.select(query).map((row) {
      return EncryptedVaultItem(
        id: row['id'] as String,
        encryptedBlob: row['encrypted_blob'] as String,
        nonce: row['nonce'] as String,
        version: row['version'] as int,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDeleted: (row['is_deleted'] as int) == 1,
      );
    }).toList();
  }

  @override
  void clear() {
    db.execute('DELETE FROM vault_items');
  }
}
