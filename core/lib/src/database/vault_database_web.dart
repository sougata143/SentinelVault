import '../models/models.dart';
import 'vault_database_interface.dart';

/// Pure-Dart in-memory [VaultDatabase] implementation for the web platform.
///
/// On web, `dart:ffi` is unavailable so `package:sqlite3` cannot be used.
/// This implementation stores vault items in a [Map] in memory — identical
/// behaviour to the native in-memory SQLite path used for demos and tests.
///
/// Security note: this is appropriate for the web demo build.  A production
/// web vault would use IndexedDB + WebCrypto for persistence, but that is
/// out of scope for the current phase.
class SqliteVaultDatabase implements VaultDatabase {
  // Internal store: id → item.
  final Map<String, EncryptedVaultItem> _store = {};
  bool _opened = false;

  /// Named constructors mirror the native implementation so call sites are
  /// identical across platforms.
  SqliteVaultDatabase(String dbPath);

  /// Creates an in-memory web stub (no SQLite on web).
  SqliteVaultDatabase.inMemory();

  @override
  void open(List<int> encryptionKey) {
    _opened = true;
    // No-op: nothing to open for a Map-backed store.
    // The encryption key parameter is accepted and ignored on web —
    // the web build is a demo and does not persist data.
  }

  @override
  void close() {
    _opened = false;
    _store.clear();
  }

  void _assertOpen() {
    if (!_opened) throw StateError('Database is not open. Call open() first.');
  }

  @override
  void insertItem(EncryptedVaultItem item) {
    _assertOpen();
    _store[item.id] = item;
  }

  @override
  void updateItem(EncryptedVaultItem item) {
    _assertOpen();
    _store[item.id] = item;
  }

  @override
  void softDeleteItem(String id) {
    _assertOpen();
    final item = _store[id];
    if (item == null || item.isDeleted) return;
    _store[id] = EncryptedVaultItem(
      id: item.id,
      encryptedBlob: item.encryptedBlob,
      nonce: item.nonce,
      version: item.version + 1,
      updatedAt: DateTime.now().toUtc(),
      isDeleted: true,
    );
  }

  @override
  void hardDeleteItem(String id) {
    _assertOpen();
    _store.remove(id);
  }

  @override
  EncryptedVaultItem? getItem(String id) {
    _assertOpen();
    return _store[id];
  }

  @override
  List<EncryptedVaultItem> getAllItems({bool includeDeleted = false}) {
    _assertOpen();
    return _store.values
        .where((item) => includeDeleted || !item.isDeleted)
        .toList();
  }

  @override
  void clear() {
    _assertOpen();
    _store.clear();
  }
}
