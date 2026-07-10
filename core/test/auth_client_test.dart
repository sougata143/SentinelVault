import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';

void main() {
  group('AuthClient Unit Tests', () {
    test('Successful registration sends correct payload', () async {
      var requestBodyChecked = false;

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/auth/register');
        expect(request.headers['Content-Type'], 'application/json');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['username'], 'test@example.com');
        expect(body['salt'], isNotEmpty);
        expect(body['verifier'], isNotEmpty);
        requestBodyChecked = true;

        return http.Response(json.encode({'success': true}), 201);
      });

      final client = AuthClient(baseUrl: 'http://localhost:3003', httpClient: mockClient);
      await client.register('test@example.com', 'mypassword123');

      expect(requestBodyChecked, isTrue);
    });

    test('Registration fails on duplicate email (status 409)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(json.encode({'message': 'Username already exists'}), 409);
      });

      final client = AuthClient(baseUrl: 'http://localhost:3003', httpClient: mockClient);

      expect(
        () => client.register('duplicate@example.com', 'password'),
        throwsA(isA<DuplicateEmailException>()),
      );
    });

    test('Registration fails on other server error (status 500)', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final client = AuthClient(baseUrl: 'http://localhost:3003', httpClient: mockClient);

      expect(
        () => client.register('error@example.com', 'password'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
