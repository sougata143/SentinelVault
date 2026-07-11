import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:core/src/crypto/srp.dart';

void main() {
  group('AuthClient Login Unit Tests', () {
    const email = 'user@example.com';
    const password = 'mypassword123';
    final passwordBytes = utf8.encode(password);
    final salt = List<int>.generate(16, (i) => i + 1);

    test('Successful login handshakes correctly using SRP-6a', () async {
      final crypto = VaultCrypto();
      final verifier = await SrpClient.calculateVerifier(email, passwordBytes, salt);

      // Server ephemeral b
      final bRandomBytes = List<int>.generate(32, (i) => i * 2);
      final b = SrpClient.bytesToBigInt(bRandomBytes) % SrpClient.N;
      final k = await SrpClient.getMultiplierK();
      final gb = SrpClient.g.modPow(b, SrpClient.N);
      final kv = (k * verifier) % SrpClient.N;
      final B = (kv + gb) % SrpClient.N;

      late BigInt A;
      late List<int> M1;
      late List<int> expectedM2;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/auth/login/step1') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['username'], email);
          A = BigInt.parse(body['A'] as String, radix: 16);

          final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          final bHex = B.toRadixString(16);

          return http.Response(
            json.encode({
              'challengeId': 'test-challenge-123',
              'salt': saltHex,
              'B': bHex,
            }),
            200,
          );
        } else if (request.url.path == '/auth/login/step2') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['challengeId'], 'test-challenge-123');

          final m1Hex = body['M1'] as String;
          // Decode client evidence M1
          final len = m1Hex.length ~/ 2;
          M1 = Uint8List(len);
          for (var i = 0; i < len; i++) {
            M1[i] = int.parse(m1Hex.substring(i * 2, i * 2 + 2), radix: 16);
          }

          // Server derives shared session secret S
          final aBytes = SrpClient.bigIntToBytesPadded(A, 256);
          final bBytes = SrpClient.bigIntToBytesPadded(B, 256);
          final uInput = Uint8List(aBytes.length + bBytes.length);
          uInput.setRange(0, aBytes.length, aBytes);
          uInput.setRange(aBytes.length, uInput.length, bBytes);
          final uHash = await SrpClient.sha256Hash(uInput);
          final u = SrpClient.bytesToBigInt(uHash);

          // S = (A * v^u) ^ b mod N
          final vu = verifier.modPow(u, SrpClient.N);
          final base = (A * vu) % SrpClient.N;
          final S = base.modPow(b, SrpClient.N);
          final sBytes = SrpClient.bigIntToBytesPadded(S, 256);
          final sessionKey = await SrpClient.sha256Hash(sBytes);

          // Server calculates server proof M2 = H(A, M1, sessionKey)
          final m2Input = Uint8List(256 + 32 + 32);
          m2Input.setRange(0, 256, aBytes);
          m2Input.setRange(256, 256 + 32, M1);
          m2Input.setRange(256 + 32, m2Input.length, sessionKey);
          final m2Bytes = await SrpClient.sha256Hash(m2Input);

          final serverEvidenceHex = m2Bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

          return http.Response(
            json.encode({
              'serverEvidence': serverEvidenceHex,
              'token': 'success-token-xyz',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = AuthClient(baseUrl: 'http://localhost:3003', httpClient: mockClient);
      final token = await client.login(email, password);

      expect(token, 'success-token-xyz');
    });

    test('Incorrect password fails generically on step 2', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/auth/login/step1') {
          return http.Response(
            json.encode({
              'challengeId': 'test-challenge-123',
              'salt': '01020304',
              'B': 'aabbcc',
            }),
            200,
          );
        } else if (request.url.path == '/auth/login/step2') {
          return http.Response('Unauthorized', 401);
        }
        return http.Response('Not Found', 404);
      });

      final client = AuthClient(baseUrl: 'http://localhost:3003', httpClient: mockClient);
      expect(
        () => client.login(email, password),
        throwsA(isA<Exception>()),
      );
    });
  });
}
