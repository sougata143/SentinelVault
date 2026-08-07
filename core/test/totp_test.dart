import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('TOTP / Authenticator Core Tests', () {
    test('Base32 decoding test', () {
      expect(TotpHelper.decodeBase32('JBSWY3DPEE======'), equals(utf8.encode('Hello!')));
      expect(TotpHelper.decodeBase32('JBSWY3DPEE'), equals(utf8.encode('Hello!')));
    });

    test('RFC 6238 SHA-1 Test Vectors (20-byte key: 12345678901234567890)', () {
      final keyBytes = Uint8List.fromList(utf8.encode('12345678901234567890'));

      final testCases = [
        (59, '287082', '94287082'),
        (1111111109, '081804', '07081804'),
        (1111111111, '050471', '14050471'),
        (1234567890, '005924', '89005924'),
        (2000000000, '279037', '69279037'),
      ];

      for (final (t, exp6, exp8) in testCases) {
        final code6 = TotpHelper.generateTotpFromBytes(
          keyBytes: keyBytes,
          timestampSec: t,
          period: 30,
          digits: 6,
          algorithm: 'SHA1',
        );
        expect(code6, equals(exp6), reason: 'Failed 6-digit SHA1 for t=$t');

        final code8 = TotpHelper.generateTotpFromBytes(
          keyBytes: keyBytes,
          timestampSec: t,
          period: 30,
          digits: 8,
          algorithm: 'SHA1',
        );
        expect(code8, equals(exp8), reason: 'Failed 8-digit SHA1 for t=$t');
      }
    });

    test('RFC 6238 SHA-256 Test Vectors (32-byte key: 12345678901234567890123456789012)', () {
      final keyBytes = Uint8List.fromList(utf8.encode('12345678901234567890123456789012'));

      final testCases = [
        (59, '46119246'),
        (1111111109, '68084774'),
        (1111111111, '67062674'),
        (1234567890, '91819424'),
        (2000000000, '90698825'),
      ];

      for (final (t, exp8) in testCases) {
        final code8 = TotpHelper.generateTotpFromBytes(
          keyBytes: keyBytes,
          timestampSec: t,
          period: 30,
          digits: 8,
          algorithm: 'SHA256',
        );
        expect(code8, equals(exp8), reason: 'Failed 8-digit SHA256 for t=$t');
      }
    });

    test('RFC 6238 SHA-512 Test Vectors (64-byte key)', () {
      final keyBytes = Uint8List.fromList(utf8.encode('1234567890123456789012345678901234567890123456789012345678901234'));

      final testCases = [
        (59, '90693936'),
        (1111111109, '25091201'),
        (1111111111, '99943326'),
        (1234567890, '93441116'),
        (2000000000, '38618901'),
      ];

      for (final (t, exp8) in testCases) {
        final code8 = TotpHelper.generateTotpFromBytes(
          keyBytes: keyBytes,
          timestampSec: t,
          period: 30,
          digits: 8,
          algorithm: 'SHA512',
        );
        expect(code8, equals(exp8), reason: 'Failed 8-digit SHA512 for t=$t');
      }
    });

    test('otpauth:// URI parsing', () {
      const uri = 'otpauth://totp/GitHub:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256&digits=8&period=60';
      final params = TotpHelper.parseOtpauthUri(uri);

      expect(params.issuer, equals('GitHub'));
      expect(params.accountName, equals('user@example.com'));
      expect(params.secret, equals('JBSWY3DPEHPK3PXP'));
      expect(params.algorithm, equals('SHA256'));
      expect(params.digits, equals(8));
      expect(params.period, equals(60));
    });

    test('TotpFields encryption and decryption pipeline', () async {
      final crypto = VaultCrypto();
      final vaultKey = crypto.generateRandomBytes(32);

      final fields = TotpFields(
        issuer: 'GitHub',
        accountName: 'test@sentinelvault.local',
        secret: const ConcealedValue.plain('JBSWY3DPEHPK3PXP'),
        algorithm: 'SHA1',
        digits: 6,
        period: 30,
      );

      final encFields = await fields.encrypt(vaultKey, crypto);
      expect(encFields.secret.isEncrypted, isTrue);

      final decFields = await encFields.decrypt(vaultKey, crypto);
      expect(decFields.secret.plaintext, equals('JBSWY3DPEHPK3PXP'));
    });
  });
}
