import 'dart:convert';

/// A single security activity event recorded locally on-device.
///
/// Security invariant: This object NEVER stores vault item content, passwords,
/// usernames, or any other sensitive field — only metadata (type, count, time).
class SecurityActivity {
  /// Human-readable label for the activity type.
  /// Examples: 'encrypted_backup_export', 'plaintext_csv_export', 'vault_import'
  final String type;

  /// Number of items involved in the event.
  final int itemCount;

  /// UTC timestamp when the activity occurred.
  final DateTime timestamp;

  /// Creates a new [SecurityActivity] record with the given metadata.
  const SecurityActivity({
    required this.type,
    required this.itemCount,
    required this.timestamp,
  });

  /// Serializes the security activity record into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'type': type,
        'itemCount': itemCount,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Creates a [SecurityActivity] record from a deserialized JSON map.
  factory SecurityActivity.fromJson(Map<String, dynamic> json) =>
      SecurityActivity(
        type: json['type'] as String,
        itemCount: json['itemCount'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Local security activity log — records metadata-only events for user review.
///
/// All data is in-memory in this implementation; a persistent variant
/// would flush to SQLite. The log is device-local and never synced to the
/// backend or any third-party service.
///
/// Security invariant: Only [type], [itemCount], and [timestamp] are ever
/// stored. Callers MUST NOT pass item content, passwords, or key material.
class SecurityActivityLog {
  // Singleton so the same log is visible across the app session.
  SecurityActivityLog._();

  /// The global singleton instance of the [SecurityActivityLog].
  static final SecurityActivityLog instance = SecurityActivityLog._();

  final List<SecurityActivity> _entries = [];

  /// Appends an export event to the log.
  ///
  /// [type] should be a short identifier such as `'encrypted_backup_export'`
  /// or `'plaintext_csv_export'`. [itemCount] is the number of items exported.
  ///
  /// Security invariant: Do NOT pass any vault item content as part of [type].
  void logExport({
    required String type,
    required int itemCount,
    required DateTime timestamp,
  }) {
    _entries.add(SecurityActivity(
      type: type,
      itemCount: itemCount,
      timestamp: timestamp,
    ));
  }

  /// Appends a generic activity event (import, unlock, etc.).
  void logActivity({
    required String type,
    required int itemCount,
  }) {
    _entries.add(SecurityActivity(
      type: type,
      itemCount: itemCount,
      timestamp: DateTime.now().toUtc(),
    ));
  }

  /// Returns all log entries, newest first.
  List<SecurityActivity> getLog() {
    return List.unmodifiable(
      _entries.toList().reversed.toList(),
    );
  }

  /// Serialises the log to a JSON string (for display in the Security Center).
  String toJson() => jsonEncode(_entries.map((e) => e.toJson()).toList());

  /// Clears all entries (used on logout / vault lock).
  void clear() => _entries.clear();
}
