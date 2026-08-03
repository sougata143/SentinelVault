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

  /// Ensures the current user has PQC keys generated locally and published to key-directory.
  static Future<void> ensureKeysPublished(String userEmail) async {
    try {
      final token = await _storage.read(key: 'session_token') ?? '';
      if (token.isEmpty) return;

      String? x25519PrivStr = await _storage.read(key: 'pqc_x25519_priv');
      String? ed25519PrivStr = await _storage.read(key: 'pqc_ed25519_priv');
      String? mlkemDkStr = await _storage.read(key: 'pqc_mlkem_dk');
      String? mldsaSeedStr = await _storage.read(key: 'pqc_mldsa_seed');

      PqcKeyBundle bundle;
      if (x25519PrivStr == null || ed25519PrivStr == null || mlkemDkStr == null || mldsaSeedStr == null) {
        bundle = await _bridge.pqcGenerateKeypairs();
        await _storage.write(key: 'pqc_x25519_priv', value: base64Url.encode(bundle.x25519Priv));
        await _storage.write(key: 'pqc_ed25519_priv', value: base64Url.encode(bundle.ed25519Priv));
        await _storage.write(key: 'pqc_mlkem_dk', value: base64Url.encode(bundle.mlkemDk));
        await _storage.write(key: 'pqc_mldsa_seed', value: base64Url.encode(bundle.mldsaSeed));
        await _storage.write(key: 'pqc_x25519_pub', value: base64Url.encode(bundle.x25519Pub));
        await _storage.write(key: 'pqc_ed25519_pub', value: base64Url.encode(bundle.ed25519Pub));
        await _storage.write(key: 'pqc_mlkem_ek', value: base64Url.encode(bundle.mlkemEk));
        await _storage.write(key: 'pqc_mldsa_vk', value: base64Url.encode(bundle.mldsaVk));
      } else {
        final x25519PubStr = await _storage.read(key: 'pqc_x25519_pub') ?? '';
        final ed25519PubStr = await _storage.read(key: 'pqc_ed25519_pub') ?? '';
        final mlkemEkStr = await _storage.read(key: 'pqc_mlkem_ek') ?? '';
        final mldsaVkStr = await _storage.read(key: 'pqc_mldsa_vk') ?? '';

        bundle = PqcKeyBundle(
          x25519Pub: base64Url.decode(x25519PubStr),
          x25519Priv: base64Url.decode(x25519PrivStr),
          ed25519Pub: base64Url.decode(ed25519PubStr),
          ed25519Priv: base64Url.decode(ed25519PrivStr),
          mlkemEk: base64Url.decode(mlkemEkStr),
          mlkemDk: base64Url.decode(mlkemDkStr),
          mldsaVk: base64Url.decode(mldsaVkStr),
          mldsaSeed: base64Url.decode(mldsaSeedStr),
        );
      }

      // Resolve userId by email
      final lookupRes = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/auth/users/lookup?email=${Uri.encodeComponent(userEmail)}'),
      );
      if (lookupRes.statusCode != 200) return;
      final lookupData = json.decode(lookupRes.body) as Map<String, dynamic>;
      if (lookupData['ok'] != true || lookupData['userId'] == null) return;
      final userId = lookupData['userId'] as String;

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
      );
    } catch (_) {
      // Background publish fallback
    }
  }

  /// Syncs shared items for folders shared with the calling user.
  static Future<List<Map<String, dynamic>>> syncSharedFoldersWithMe() async {
    try {
      final token = await _storage.read(key: 'session_token') ?? '';
      if (token.isEmpty) return [];

      final x25519PrivStr = await _storage.read(key: 'pqc_x25519_priv');
      final mlkemDkStr = await _storage.read(key: 'pqc_mlkem_dk');
      if (x25519PrivStr == null || mlkemDkStr == null) return [];

      final x25519Priv = base64Url.decode(x25519PrivStr);
      final mlkemDk = base64Url.decode(mlkemDkStr);

      final res = await http.get(
        Uri.parse('${ApiConfig.sharingBaseUrl}/key-directory/my-shares'),
        headers: {'Authorization': 'Bearer $token'},
      );

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
}
