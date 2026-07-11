import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'sync.dart';

/// HTTP implementation of the remote Sync API client.
class HttpSyncApiClient implements SyncApiClient {
  final String baseUrl;
  final String userId;
  final http.Client _httpClient;

  /// Creates a new [HttpSyncApiClient].
  HttpSyncApiClient({
    required this.baseUrl,
    required this.userId,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  @override
  Future<List<EncryptedVaultItem>> pull() async {
    final url = Uri.parse('$baseUrl/sync/pull');
    final response = await _httpClient.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to pull items: ${response.statusCode}');
    }

    final List<dynamic> data = json.decode(response.body);
    return data.map((jsonItem) {
      return EncryptedVaultItem(
        id: jsonItem['id'] as String,
        encryptedBlob: jsonItem['encryptedBlob'] as String,
        nonce: jsonItem['nonce'] as String,
        version: jsonItem['version'] as int,
        updatedAt: DateTime.parse(jsonItem['updatedAt'] as String).toUtc(),
        isDeleted: jsonItem['isDeleted'] as bool? ?? false,
      );
    }).toList();
  }

  @override
  Future<SyncPushResult> push(List<EncryptedVaultItem> items) async {
    final url = Uri.parse('$baseUrl/sync/push');
    final body = items.map((item) => {
      'id': item.id,
      'encryptedBlob': item.encryptedBlob,
      'nonce': item.nonce,
      'version': item.version,
      'updatedAt': item.updatedAt.toIso8601String(),
      'isDeleted': item.isDeleted,
    }).toList();

    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
      body: json.encode(body),
    );

    if (response.statusCode == 409) {
      final data = json.decode(response.body);
      final List<dynamic> conflictList = data['conflicts'];
      final conflicts = conflictList.map((jsonItem) {
        return EncryptedVaultItem(
          id: jsonItem['id'] as String,
          encryptedBlob: jsonItem['encryptedBlob'] as String,
          nonce: jsonItem['nonce'] as String,
          version: jsonItem['version'] as int,
          updatedAt: DateTime.parse(jsonItem['updatedAt'] as String).toUtc(),
          isDeleted: jsonItem['isDeleted'] as bool? ?? false,
        );
      }).toList();
      return SyncPushResult.conflict(conflicts);
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to push items: ${response.statusCode}');
    }

    return SyncPushResult.success();
  }

  /// Uploads the master KDF salt and the wrapped vault key to the sync server.
  Future<void> uploadVaultKey({
    required String saltHex,
    required String wrappedKeyHex,
    String? recoverySaltHex,
    String? recoveryWrappedKeyHex,
  }) async {
    final url = Uri.parse('$baseUrl/sync/vault-key');
    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
      body: json.encode({
        'salt': saltHex,
        'wrappedKey': wrappedKeyHex,
        if (recoverySaltHex != null) 'recoverySalt': recoverySaltHex,
        if (recoveryWrappedKeyHex != null) 'recoveryWrappedKey': recoveryWrappedKeyHex,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload vault key: ${response.statusCode}');
    }
  }

  /// Fetches the master KDF salt and the wrapped vault key from the sync server.
  Future<Map<String, String>> fetchVaultKey() async {
    final url = Uri.parse('$baseUrl/sync/vault-key');
    final response = await _httpClient.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
    );

    if (response.statusCode == 404) {
      throw Exception('Vault key not found');
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch vault key: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return {
      'salt': data['salt'] as String,
      'wrappedKey': data['wrappedKey'] as String,
      if (data['recoverySalt'] != null) 'recoverySalt': data['recoverySalt'] as String,
      if (data['recoveryWrappedKey'] != null) 'recoveryWrappedKey': data['recoveryWrappedKey'] as String,
    };
  }
}
