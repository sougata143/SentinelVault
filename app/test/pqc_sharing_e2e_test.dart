@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core/core.dart';
import 'package:app/config/api_config.dart';

void main() {
  final httpClient = http.Client();
  final bridge = getNativeCryptoBridge();
  final sharingManager = PqcSharingManager(bridge);
  final crypto = VaultCrypto(bridge: bridge);

  test('E2E PQC Hybrid Sharing Pass: Test-A shares with Test-B, Test-B decrypts, Test-C rejected with 404', () async {
    final authBaseUrl = ApiConfig.authBaseUrl.isNotEmpty ? ApiConfig.authBaseUrl : 'http://localhost:3001';
    final sharingBaseUrl = ApiConfig.sharingBaseUrl.isNotEmpty ? ApiConfig.sharingBaseUrl : 'http://localhost:3004';

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final emailA = 'test-a-$timestamp@example.com';
    final emailB = 'test-b-$timestamp@example.com';
    final emailC = 'test-c-$timestamp@example.com';
    const password = 'Password123!';

    // 1. Register users test-a, test-b, test-c via Auth API
    final saltA = crypto.generateRandomBytes(16);
    final saltB = crypto.generateRandomBytes(16);
    final saltC = crypto.generateRandomBytes(16);

    final mkA = await crypto.deriveMasterKey(masterPassword: password, salt: saltA);
    final verifierA = await SrpClient.calculateVerifier(emailA, mkA, saltA);
    final regResA = await httpClient.post(
      Uri.parse('$authBaseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': emailA,
        'salt': saltA.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'verifier': verifierA.toRadixString(16),
      }),
    );
    expect(regResA.statusCode, equals(201));
    final tokenA = (json.decode(regResA.body) as Map<String, dynamic>)['token'] as String;

    final mkB = await crypto.deriveMasterKey(masterPassword: password, salt: saltB);
    final verifierB = await SrpClient.calculateVerifier(emailB, mkB, saltB);
    final regResB = await httpClient.post(
      Uri.parse('$authBaseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': emailB,
        'salt': saltB.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'verifier': verifierB.toRadixString(16),
      }),
    );
    expect(regResB.statusCode, equals(201));
    final tokenB = (json.decode(regResB.body) as Map<String, dynamic>)['token'] as String;

    final mkC = await crypto.deriveMasterKey(masterPassword: password, salt: saltC);
    final verifierC = await SrpClient.calculateVerifier(emailC, mkC, saltC);
    final regResC = await httpClient.post(
      Uri.parse('$authBaseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': emailC,
        'salt': saltC.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'verifier': verifierC.toRadixString(16),
      }),
    );
    expect(regResC.statusCode, equals(201));
    final tokenC = (json.decode(regResC.body) as Map<String, dynamic>)['token'] as String;

    // 2. Lookup user IDs for test-a and test-b
    final lookupResA = await httpClient.get(
      Uri.parse('$authBaseUrl/auth/users/lookup?email=$emailA'),
    );
    expect(lookupResA.statusCode, equals(200));
    final userIdA = (json.decode(lookupResA.body) as Map<String, dynamic>)['userId'] as String;

    final lookupResB = await httpClient.get(
      Uri.parse('$authBaseUrl/auth/users/lookup?email=$emailB'),
    );
    expect(lookupResB.statusCode, equals(200));
    final userIdB = (json.decode(lookupResB.body) as Map<String, dynamic>)['userId'] as String;

    // 3. Generate and publish PQC Key Bundles for test-a and test-b
    final bundleA = await bridge.pqcGenerateKeypairs();
    final fpA = await sharingManager.computeSafetyNumber(bundleA);
    final pubResA = await httpClient.post(
      Uri.parse('$sharingBaseUrl/key-directory/keys'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $tokenA',
      },
      body: json.encode({
        'userId': userIdA,
        'x25519PublicKey': base64Url.encode(bundleA.x25519Pub),
        'ed25519PublicKey': base64Url.encode(bundleA.ed25519Pub),
        'mlkemEncapsulationKey': base64Url.encode(bundleA.mlkemEk),
        'mldsaVerifyingKey': base64Url.encode(bundleA.mldsaVk),
        'keyFingerprint': fpA,
      }),
    );
    expect(pubResA.statusCode, equals(200));

    final bundleB = await bridge.pqcGenerateKeypairs();
    final fpB = await sharingManager.computeSafetyNumber(bundleB);
    final pubResB = await httpClient.post(
      Uri.parse('$sharingBaseUrl/key-directory/keys'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $tokenB',
      },
      body: json.encode({
        'userId': userIdB,
        'x25519PublicKey': base64Url.encode(bundleB.x25519Pub),
        'ed25519PublicKey': base64Url.encode(bundleB.ed25519Pub),
        'mlkemEncapsulationKey': base64Url.encode(bundleB.mlkemEk),
        'mldsaVerifyingKey': base64Url.encode(bundleB.mldsaVk),
        'keyFingerprint': fpB,
      }),
    );
    expect(pubResB.statusCode, equals(200));

    // 4. Test-a creates a Folder Key & encrypts a secret vault payload
    final folderId = 'a1b2c3d4-e5f6-47fa-b9ca-${timestamp.toRadixString(16).padLeft(12, '0')}';
    final folderKey = crypto.generateRandomBytes(32);
    final plaintext = utf8.encode('Top Secret Shared Password 123');
    final nonce = crypto.generateRandomBytes(12);
    final ciphertext = await crypto.encryptAesGcm(
      plaintext: Uint8List.fromList(plaintext),
      key: folderKey,
      nonce: nonce,
    );

    // 5. Test-a fetches Test-b's public key bundle
    final fetchResB = await httpClient.get(
      Uri.parse('$sharingBaseUrl/key-directory/keys/$userIdB'),
      headers: {'Authorization': 'Bearer $tokenA'},
    );
    expect(fetchResB.statusCode, equals(200));
    final bData = json.decode(fetchResB.body) as Map<String, dynamic>;

    final recipientBundleB = PqcKeyBundle(
      x25519Pub: base64Url.decode(bData['x25519PublicKey'] as String),
      x25519Priv: Uint8List(32),
      ed25519Pub: base64Url.decode(bData['ed25519PublicKey'] as String),
      ed25519Priv: Uint8List(32),
      mlkemEk: base64Url.decode(bData['mlkemEncapsulationKey'] as String),
      mlkemDk: Uint8List(2400),
      mldsaVk: base64Url.decode(bData['mldsaVerifyingKey'] as String),
      mldsaSeed: Uint8List(32),
    );

    // 6. Test-a performs PQC Hybrid Wrap for Test-b
    final invitation = await sharingManager.createSignedInvitation(
      folderId: folderId,
      recipientUserId: userIdB,
      senderUserId: userIdA,
      ed25519Priv: bundleA.ed25519Priv,
      mldsaSeed: bundleA.mldsaSeed,
      folderKey: folderKey,
      recipientX25519Pub: recipientBundleB.x25519Pub,
      recipientMlkemEk: recipientBundleB.mlkemEk,
    );

    final wrappedKeyData = invitation['wrappedFolderKey'] as Map<String, dynamic>;

    // 7. Test-a publishes wrapped keys to POST /key-directory/wrapped-keys (writes to Postgres DB)
    final publishWrappedRes = await httpClient.post(
      Uri.parse('$sharingBaseUrl/key-directory/wrapped-keys'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $tokenA',
      },
      body: json.encode({
        'folderId': folderId,
        'keyVersion': '1',
        'recipients': [
          {
            'recipientUserId': userIdB,
            'ephemeralX25519PublicKey': wrappedKeyData['ephemeralX25519PublicKey'],
            'mlkemCiphertext': wrappedKeyData['mlkemCiphertext'],
            'aesNonce': wrappedKeyData['aesNonce'],
            'wrappedFolderKey': wrappedKeyData['wrappedFolderKey'],
          }
        ],
      }),
    );
    expect(publishWrappedRes.statusCode, equals(200));

    // 8. Test-b (intended recipient) fetches wrapped key
    final fetchWrappedResB = await httpClient.get(
      Uri.parse('$sharingBaseUrl/key-directory/wrapped-keys/$folderId'),
      headers: {'Authorization': 'Bearer $tokenB'},
    );
    expect(fetchWrappedResB.statusCode, equals(200));
    final wrappedRecordB = (json.decode(fetchWrappedResB.body) as Map<String, dynamic>)['record'] as Map<String, dynamic>;
    expect(wrappedRecordB['recipientUserId'], equals(userIdB));

    // 9. Test-b unwraps Folder Key using Test-b's private keys
    final recoveredFolderKeyB = await sharingManager.unwrapFolderKey(
      wrappedKeyData: wrappedRecordB,
      recipientX25519Priv: bundleB.x25519Priv,
      recipientMlkemDk: bundleB.mlkemDk,
    );
    expect(recoveredFolderKeyB, equals(folderKey));

    // 10. Test-b decrypts the shared item content
    final decryptedB = await crypto.decryptAesGcm(
      ciphertextAndMac: ciphertext,
      key: recoveredFolderKeyB,
      nonce: nonce,
    );
    expect(utf8.decode(decryptedB), equals('Top Secret Shared Password 123'));

    // 11. Test-c (uninvited third party) attempts to fetch wrapped key
    final fetchWrappedResC = await httpClient.get(
      Uri.parse('$sharingBaseUrl/key-directory/wrapped-keys/$folderId'),
      headers: {'Authorization': 'Bearer $tokenC'},
    );
    expect(fetchWrappedResC.statusCode, equals(404));
  });
}
