import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:core/core.dart';

/// Computes the SHA-1 hex string of [password] (uppercased).
/// Mirrors the on-device computation inside BreachMonitor — used only in tests.
String _sha1Hex(String password) =>
    sha1.convert(utf8.encode(password)).toString().toUpperCase();

void main() {
  group('BreachMonitor — k-anonymity password check', () {
    // ── Test 1: Password NOT in any breach ─────────────────────────────────
    test('1. Not-breached password returns pwnedCount == 0', () async {
      // Use a long random password unlikely to appear in any breach.
      const password = 'Tr0ub4dor&3-xkcd-correcthorsebatterystaple-unique!';
      final fullHash = _sha1Hex(password);
      final prefix = fullHash.substring(0, 5);
      final suffix = fullHash.substring(5);

      // Build a mock response that contains OTHER suffixes but NOT ours.
      final otherSuffix = '${suffix.substring(1)}A'; // shift by one char
      final mockBody = '$otherSuffix:1234\nFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:0\n';

      final client = MockClient((_) async => http.Response(mockBody, 200));
      final monitor = BreachMonitor(client: client);
      final result = await monitor.checkPassword(password);

      expect(result.pwnedCount, equals(0));
      expect(result.isBreached, isFalse);
      expect(result.prefix, equals(prefix));

      monitor.dispose();
    });

    // ── Test 2: Breached password returns correct count ────────────────────
    test('2. Breached password returns correct pwnedCount', () async {
      const password = 'password'; // extremely common
      final fullHash = _sha1Hex(password);
      final prefix = fullHash.substring(0, 5);
      final suffix = fullHash.substring(5);

      // Mock response includes our suffix with a large count.
      final mockBody =
          'AABBCCDDEEFF00112233445566778899AABBCC:42\n'
          '$suffix:3730471\n'
          'FFEEDDCCBBAA00112233445566778899AABBCC:1\n';

      final client = MockClient((_) async => http.Response(mockBody, 200));
      final monitor = BreachMonitor(client: client);
      final result = await monitor.checkPassword(password);

      expect(result.pwnedCount, equals(3730471));
      expect(result.isBreached, isTrue);
      expect(result.prefix, equals(prefix));

      monitor.dispose();
    });

    // ── Test 3: Only 5-char prefix is sent in the outbound URL ────────────
    test('3. Only the 5-char SHA-1 prefix is in the request URL', () async {
      const password = 'hunter2';
      final fullHash = _sha1Hex(password);
      final prefix = fullHash.substring(0, 5);
      final suffix = fullHash.substring(5);

      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        // Return a response that does NOT include our suffix → count 0.
        return http.Response(
          'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:0\n',
          200,
        );
      });

      final monitor = BreachMonitor(client: client);
      await monitor.checkPassword(password);

      expect(capturedUri, isNotNull);

      // The URL path must end with exactly the 5-char prefix.
      expect(
        capturedUri!.path.endsWith(prefix),
        isTrue,
        reason: 'URL path should end with the 5-char prefix "$prefix"',
      );

      // The full 40-char hash must NOT appear in the URL.
      final fullUrl = capturedUri.toString();
      expect(
        fullUrl.contains(fullHash),
        isFalse,
        reason: 'Full SHA-1 hash must never appear in the request URL',
      );

      // The 35-char suffix must NOT appear in the URL.
      expect(
        fullUrl.contains(suffix),
        isFalse,
        reason: 'SHA-1 suffix must never appear in the request URL',
      );

      monitor.dispose();
    });

    // ── Test 4: Zero-count padding entries are filtered out ────────────────
    test('4. Padding entries (count == 0) are not treated as breached', () async {
      const password = 'PaddingTestPassword123';
      final fullHash = _sha1Hex(password);
      final suffix = fullHash.substring(5);

      // Our suffix appears in the response but with count = 0 (HIBP padding).
      final mockBody = '$suffix:0\nABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFF:12\n';

      final client = MockClient((_) async => http.Response(mockBody, 200));
      final monitor = BreachMonitor(client: client);
      final result = await monitor.checkPassword(password);

      expect(
        result.pwnedCount,
        equals(0),
        reason: 'A zero-count padding entry must not be treated as a breach',
      );
      expect(result.isBreached, isFalse);

      monitor.dispose();
    });

    // ── Test 5: Empty password bypasses network and returns safe result ────
    test('5. Empty password returns safe result without any network call', () async {
      var requestMade = false;
      final client = MockClient((_) async {
        requestMade = true;
        return http.Response('', 200);
      });

      final monitor = BreachMonitor(client: client);
      final result = await monitor.checkPassword('');

      expect(result.pwnedCount, equals(0));
      expect(result.isBreached, isFalse);
      expect(
        requestMade,
        isFalse,
        reason: 'No HTTP request should fire for an empty password',
      );

      monitor.dispose();
    });

    // ── Test 6: Non-200 response throws BreachCheckException ──────────────
    test('6. Non-200 HTTP response throws BreachCheckException', () async {
      final client = MockClient(
        (_) async => http.Response('Service Unavailable', 503),
      );

      final monitor = BreachMonitor(client: client);

      await expectLater(
        () => monitor.checkPassword('somepassword'),
        throwsA(isA<BreachCheckException>()),
      );

      monitor.dispose();
    });
  });
}
