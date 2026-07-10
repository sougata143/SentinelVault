/// Platform-adaptive vault database entry point.
///
/// Exports [VaultDatabase] (the abstract interface) and the correct
/// [SqliteVaultDatabase] concrete class for the current compile target:
///
/// - **Web** (`dart.library.html`): [vault_database_web.dart]  
///   Pure-Dart Map-backed store — no `dart:ffi` / `sqlite3`.
/// - **Native** (Android / iOS / macOS / Linux / Windows): [vault_database_io.dart]  
///   Full SQLite implementation via `package:sqlite3`.
///
/// All application code imports this file only.
library vault_database;

export 'vault_database_interface.dart' show VaultDatabase;
export 'vault_database_io.dart'
    if (dart.library.html) 'vault_database_web.dart';

