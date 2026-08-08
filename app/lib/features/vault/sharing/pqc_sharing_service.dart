import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:core/core.dart';
import '../../../config/api_config.dart';

class PqcSharingService {
  static const _storage = FlutterSecureStorage();
  static final _bridge = getNativeCryptoBridge();
  static final _sharingManager = PqcSharingManager(_bridge);

  /// In-memory cache of unwrapped folder keys mapped by folderId
  static final Map<String, Uint8List> unwrappedFolderKeys = {};

  static String _prefix(String email) => 'pqc_${email.trim().toLowerCase()}_';

  /// Restores cached unwrapped folder keys from secure storage into memory.
  static Future<void> loadCachedFolderKeys([String? email]) async {
    try {
      final activeEmail = email ?? await _storage.read(key: 'active_user_email') ?? '';
      if (activeEmail.isEmpty) return;

      final keyPrefix = '${_prefix(activeEmail)}folder_key_';
      final allKeys = await _storage.readAll();
      for (final entry in allKeys.entries) {
        if (entry.key.startsWith(keyPrefix)) {
          final folderId = entry.key.substring(keyPrefix.length);
          if (folderId.isNotEmpty && entry.value.isNotEmpty) {
            unwrappedFolderKeys[folderId] = _safeBase64Decode(entry.value);
          }
        }
      }
    } catch (_) {}
  }

  /// Ensures the current user has PQC keys generated locally and published to key-directory.
  static Future<void> ensureKeysPublished(String userEmail) async {
    try {
      final token = await _storage.read(key: 'session_token') ?? '';
      if (token.isEmpty) return;

      final p = _prefix(userEmail);
      await _storage.write(key: 'active_user_email', value: userEmail);

      String? x25519PrivStr = await _storage.read(key: '${p}x25519_priv');
      String? ed25519PrivStr = await _storage.read(key: '${p}ed25519_priv');
      String? mlkemDkStr = await _storage.read(key: '${p}mlkem_dk');
      String? mldsaSeedStr = await _storage.read(key: '${p}mldsa_seed');

      PqcKeyBundle bundle;
      if (x25519PrivStr == null || ed25519PrivStr == null || mlkemDkStr == null || mldsaSeedStr == null) {
        bundle = await _bridge.pqcGenerateKeypairs();
        await _storage.write(key: '${p}x25519_priv', value: base64Url.encode(bundle.x25519Priv));
        await _storage.write(key: '${p}ed25519_priv', value: base64Url.encode(bundle.ed25519Priv));
        await _storage.write(key: '${p}mlkem_dk', value: base64Url.encode(bundle.mlkemDk));
        await _storage.write(key: '${p}mldsa_seed', value: base64Url.encode(bundle.mldsaSeed));
        await _storage.write(key: '${p}x25519_pub', value: base64Url.encode(bundle.x25519Pub));
        await _storage.write(key: '${p}ed25519_pub', value: base64Url.encode(bundle.ed25519Pub));
        await _storage.write(key: '${p}mlkem_ek', value: base64Url.encode(bundle.mlkemEk));
        await _storage.write(key: '${p}mldsa_vk', value: base64Url.encode(bundle.mldsaVk));
      } else {
        final x25519PubStr = await _storage.read(key: '${p}x25519_pub') ?? '';
        final ed25519PubStr = await _storage.read(key: '${p}ed25519_pub') ?? '';
        final mlkemEkStr = await _storage.read(key: '${p}mlkem_ek') ?? '';
        final mldsaVkStr = await _storage.read(key: '${p}mldsa_vk') ?? '';

        bundle = PqcKeyBundle(
          x25519Pub: _safeBase64Decode(x25519PubStr),
          x25519Priv: _safeBase64Decode(x25519PrivStr),
          ed25519Pub: _safeBase64Decode(ed25519PubStr),
          ed25519Priv: _safeBase64Decode(ed25519PrivStr),
          mlkemEk: _safeBase64Decode(mlkemEkStr),
          mlkemDk: _safeBase64Decode(mlkemDkStr),
          mldsaVk: _safeBase64Decode(mldsaVkStr),
          mldsaSeed: _safeBase64Decode(mldsaSeedStr),
        );
      }

      // Resolve userId by email
      final lookupRes = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/auth/users/lookup?email=${Uri.encodeComponent(userEmail)}'),
      ).timeout(const Duration(seconds: 10), onTimeout: () => http.Response('{}', 408));
      if (lookupRes.statusCode != 200) return;
      final data = json.decode(lookupRes.body);
      if (data is! Map || data['userId'] == null) return;
      final userId = data['userId'] as String;

      final fingerprint = await _sharingManager.computeSafetyNumber(bundle);

      // Publish keys to key-directory
      await http.post(
        Uri.parse('${ApiConfig.sharingBaseUrl}/key-directory/keys'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'userId': userId,
          'x25519PublicKey': base64Url.encode(bundle.x25519Pub),
          'ed25519PublicKey': base64Url.encode(bundle.ed25519Pub),
          'mlkemEncapsulationKey': base64Url.encode(bundle.mlkemEk),
          'mldsaVerifyingKey': base64Url.encode(bundle.mldsaVk),
          'keyFingerprint': fingerprint,
        }),
      ).timeout(const Duration(seconds: 10), onTimeout: () => http.Response('{}', 408));
    } catch (_) {
      // Background publish fallback
    }
  }

  /// Syncs shared items for folders shared with the calling user.
  static Future<List<Map<String, dynamic>>> syncSharedFoldersWithMe([String? userEmail]) async {
    try {
      final activeEmail = userEmail ?? await _storage.read(key: 'active_user_email') ?? '';
      await loadCachedFolderKeys(activeEmail);

      final token = await _storage.read(key: 'session_token') ?? '';
      if (token.isEmpty) return [];

      final p = _prefix(activeEmail);
      final x25519PrivStr = await _storage.read(key: '${p}x25519_priv');
      final mlkemDkStr = await _storage.read(key: '${p}mlkem_dk');
      if (x25519PrivStr == null || mlkemDkStr == null) return [];

      final x25519Priv = _safeBase64Decode(x25519PrivStr);
      final mlkemDk = _safeBase64Decode(mlkemDkStr);

      final res = await http.get(
        Uri.parse('${ApiConfig.sharingBaseUrl}/key-directory/my-shares'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10), onTimeout: () => http.Response('{}', 408));

      if (res.statusCode != 200) return [];
      final data = json.decode(res.body) as Map<String, dynamic>;
      final List<dynamic> shares = data['shares'] ?? [];

      final List<Map<String, dynamic>> unwrappedShares = [];

      for (final share in shares) {
        final folderId = share['folderId'] as String;
        final record = share['record'] as Map<String, dynamic>;
        try {
          final recoveredFolderKey = await _sharingManager.unwrapFolderKey(
            wrappedKeyData: record,
            recipientX25519Priv: x25519Priv,
            recipientMlkemDk: mlkemDk,
          );

          unwrappedFolderKeys[folderId] = recoveredFolderKey;
          if (activeEmail.isNotEmpty) {
            await _storage.write(
              key: '${p}folder_key_$folderId',
              value: base64Url.encode(recoveredFolderKey),
            );
          }

          unwrappedShares.add({
            'folderId': folderId,
            'folderKey': recoveredFolderKey,
          });
        } catch (_) {
          // Key unwrap error
        }
      }

      return unwrappedShares;
    } catch (_) {
      return [];
    }
  }

  static Uint8List _safeBase64Decode(String input) {
    final clean = input.replaceAll('=', '').replaceAll(' ', '').trim();
    return base64Url.decode(base64Url.normalize(clean));
  }
}
