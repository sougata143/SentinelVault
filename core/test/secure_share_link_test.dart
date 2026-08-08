import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('SecureShareHelper Client-Side Cryptographic Tests', () {
    late VaultCrypto crypto;

    setUp(() {
      crypto = VaultCrypto();
    });

    test('1. Encrypts payload with 32-byte key and decrypts cleanly client-side', () async {
      const originalJson = '{"title":"Home Wi-Fi","password":"SuperSecretWifiPass2026!"}';

      final encResult = await SecureShareHelper.encryptSharePayload(
        jsonPayload: originalJson,
        crypto: crypto,
      );

      expect(encResult.encryptedBlob, isNotEmpty);
      expect(encResult.nonce, isNotEmpty);
      expect(encResult.shareKeyHex.length, equals(64)); // 32 bytes in hex = 64 characters

      final decrypted = await SecureShareHelper.decryptSharePayload(
        encryptedBlobBase64: encResult.encryptedBlob,
        nonceBase64: encResult.nonce,
        shareKeyHex: encResult.shareKeyHex,
        crypto: crypto,
      );

      expect(decrypted, equals(originalJson));
    });

    test('2. Decryption fails if key in URL fragment is incorrect', () async {
      const originalJson = '{"secret":"DatabaseRootPassword"}';

      final encResult = await SecureShareHelper.encryptSharePayload(
        jsonPayload: originalJson,
        crypto: crypto,
      );

      final wrongKeyHex = '0' * 64;

      expect(
        () async => await SecureShareHelper.decryptSharePayload(
          encryptedBlobBase64: encResult.encryptedBlob,
          nonceBase64: encResult.nonce,
          shareKeyHex: wrongKeyHex,
          crypto: crypto,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('3. URL fragment builder and parser isolate key in # fragment', () {
      const baseUrl = 'https://sentinelvault.app';
      const shareId = '12345678-abcd-ef01-2345-6789abcdef01';
      const shareKeyHex = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

      final fullUrl = SecureShareHelper.buildShareUrl(
        baseUrl: baseUrl,
        shareId: shareId,
        shareKeyHex: shareKeyHex,
      );

      expect(fullUrl, equals('https://sentinelvault.app/share/view/12345678-abcd-ef01-2345-6789abcdef01#a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'));

      final parsed = SecureShareHelper.parseShareUrl(fullUrl);
      expect(parsed, isNotNull);
      expect(parsed!['shareId'], equals(shareId));
      expect(parsed['shareKeyHex'], equals(shareKeyHex));
    });
  });
}
