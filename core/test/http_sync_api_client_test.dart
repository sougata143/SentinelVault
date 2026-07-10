import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';

void main() {
  group('HttpSyncApiClient Unit Tests', () {
    const baseUrl = 'http://localhost:3002';
    const userId = 'user-uuid';

    test('uploadVaultKey sends correct payload', () async {
      var requestChecked = false;
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/sync/vault-key');
        expect(request.headers['x-user-id'], userId);
        expect(request.headers['Content-Type'], 'application/json');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['salt'], 'salthex');
        expect(body['wrappedKey'], 'wrappedkeyhex');
        requestChecked = true;

        return http.Response(json.encode({'success': true}), 200);
      });

      final client = HttpSyncApiClient(baseUrl: baseUrl, userId: userId, httpClient: mockClient);
      await client.uploadVaultKey(saltHex: 'salthex', wrappedKeyHex: 'wrappedkeyhex');

      expect(requestChecked, isTrue);
    });

    test('fetchVaultKey returns values on success', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/sync/vault-key');
        expect(request.headers['x-user-id'], userId);

        return http.Response(json.encode({'salt': 'salthex', 'wrappedKey': 'wrappedkeyhex'}), 200);
      });

      final client = HttpSyncApiClient(baseUrl: baseUrl, userId: userId, httpClient: mockClient);
      final result = await client.fetchVaultKey();

      expect(result['salt'], 'salthex');
      expect(result['wrappedKey'], 'wrappedkeyhex');
    });

    test('fetchVaultKey throws when vault key not found (404)', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final client = HttpSyncApiClient(baseUrl: baseUrl, userId: userId, httpClient: mockClient);
      expect(
        () => client.fetchVaultKey(),
        throwsA(isA<Exception>()),
      );
    });
  });
}
