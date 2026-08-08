import 'package:flutter_test/flutter_test.dart';
import 'package:app/config/api_config.dart';

void main() {
  group('ApiConfig Self-Hosted Custom Server URL Tests', () {
    tearDown(() {
      ApiConfig.customServerUrl = null;
    });

    test('returns empty-string (origin-relative) URLs when customServerUrl is null or empty', () {
      ApiConfig.customServerUrl = null;
      expect(ApiConfig.authBaseUrl, equals(''));
      expect(ApiConfig.syncBaseUrl, equals(''));
      expect(ApiConfig.securityBaseUrl, equals(''));
      expect(ApiConfig.sharingBaseUrl, equals(''));

      ApiConfig.customServerUrl = '   ';
      expect(ApiConfig.authBaseUrl, equals(''));
    });

    test('dynamically appends microservice ports for host-only inputs', () {
      ApiConfig.customServerUrl = 'https://vault.mycompany.com';

      expect(ApiConfig.authBaseUrl, equals('https://vault.mycompany.com:3001'));
      expect(ApiConfig.syncBaseUrl, equals('https://vault.mycompany.com:3002'));
      expect(ApiConfig.securityBaseUrl, equals('https://vault.mycompany.com:3003'));
      expect(ApiConfig.sharingBaseUrl, equals('https://vault.mycompany.com:3004'));
    });

    test('preserves explicit port or path inputs', () {
      ApiConfig.customServerUrl = 'http://192.168.1.100:3001';
      expect(ApiConfig.authBaseUrl, equals('http://192.168.1.100:3001'));

      ApiConfig.customServerUrl = 'https://vault.domain.com/auth';
      expect(ApiConfig.authBaseUrl, equals('https://vault.domain.com/auth'));
    });
  });
}
