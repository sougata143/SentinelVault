import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Parsed parameters from an `otpauth://totp/...` URI.
class TotpParams {
  /// Name of the service or issuer (e.g., 'GitHub', 'Google').
  final String issuer;

  /// Account name or email identifier (e.g., 'user@example.com').
  final String accountName;

  /// Base32 encoded TOTP secret key.
  final String secret;

  /// HMAC digest algorithm ('SHA1', 'SHA256', 'SHA512').
  final String algorithm;

  /// Number of digits in generated code (6 or 8).
  final int digits;

  /// Refresh period in seconds (30 or 60).
  final int period;

  /// Creates a new [TotpParams] instance holding parsed TOTP configuration.
  const TotpParams({
    required this.issuer,
    required this.accountName,
    required this.secret,
    this.algorithm = 'SHA1',
    this.digits = 6,
    this.period = 30,
  });
}

/// Helper class for Base32 decoding, TOTP calculation (RFC 6238), and otpauth:// parsing.
class TotpHelper {
  /// Decodes a Base32 encoded string into raw bytes.
  static Uint8List decodeBase32(String input) {
    final clean = input
        .replaceAll(RegExp(r'[\s\=\-]'), '')
        .toUpperCase();

    if (clean.isEmpty) {
      throw ArgumentError('Base32 secret cannot be empty');
    }

    int buffer = 0;
    int bitsLeft = 0;
    final List<int> result = [];

    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      int value;
      final codeUnit = char.codeUnitAt(0);

      if (codeUnit >= 65 && codeUnit <= 90) {
        // A-Z
        value = codeUnit - 65;
      } else if (codeUnit >= 50 && codeUnit <= 55) {
        // 2-7
        value = codeUnit - 50 + 26;
      } else {
        throw ArgumentError('Invalid Base32 character: $char');
      }

      buffer = (buffer << 5) | value;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        result.add((buffer >> bitsLeft) & 0xFF);
      }
    }

    return Uint8List.fromList(result);
  }

  /// Calculates a TOTP code string according to RFC 6238 and RFC 4226.
  static String generateTotpCode({
    required String secret,
    required int timestampSec,
    int period = 30,
    int digits = 6,
    String algorithm = 'SHA1',
  }) {
    final keyBytes = decodeBase32(secret);
    return generateTotpFromBytes(
      keyBytes: keyBytes,
      timestampSec: timestampSec,
      period: period,
      digits: digits,
      algorithm: algorithm,
    );
  }

  /// Calculates a TOTP code string directly from key bytes.
  static String generateTotpFromBytes({
    required Uint8List keyBytes,
    required int timestampSec,
    int period = 30,
    int digits = 6,
    String algorithm = 'SHA1',
  }) {
    final effPeriod = period <= 0 ? 30 : period;
    final effDigits = digits <= 0 ? 6 : digits;

    final counter = timestampSec ~/ effPeriod;

    // Convert counter to 8-byte big-endian Uint8List
    final counterBytes = Uint8List(8);
    var tempCounter = counter;
    for (int i = 7; i >= 0; i--) {
      counterBytes[i] = tempCounter & 0xff;
      tempCounter >>= 8;
    }

    // Select HMAC algorithm
    Hash hmacAlgo;
    final normalizedAlgo = algorithm.toUpperCase().replaceAll('-', '');
    switch (normalizedAlgo) {
      case 'SHA256':
        hmacAlgo = sha256;
        break;
      case 'SHA512':
        hmacAlgo = sha512;
        break;
      case 'SHA1':
      default:
        hmacAlgo = sha1;
        break;
    }

    final hmac = Hmac(hmacAlgo, keyBytes);
    final digest = hmac.convert(counterBytes).bytes;

    // Dynamic Truncation
    final offset = digest[digest.length - 1] & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);

    final modulus = _pow10(effDigits);
    final codeNum = binary % modulus;

    return codeNum.toString().padLeft(effDigits, '0');
  }

  static int _pow10(int exp) {
    int res = 1;
    for (int i = 0; i < exp; i++) {
      res *= 10;
    }
    return res;
  }

  /// Parses an `otpauth://totp/...` URI into [TotpParams].
  static TotpParams parseOtpauthUri(String uriString) {
    final trimmed = uriString.trim();
    if (!trimmed.toLowerCase().startsWith('otpauth://')) {
      // Treat as raw secret key string
      return TotpParams(
        issuer: '',
        accountName: '',
        secret: trimmed,
      );
    }

    final uri = Uri.parse(trimmed);
    if (uri.authority.toLowerCase() != 'totp') {
      throw ArgumentError('Unsupported otpauth type: ${uri.authority} (only totp is supported)');
    }

    final pathSegment = Uri.decodeComponent(uri.path.startsWith('/') ? uri.path.substring(1) : uri.path);
    String issuer = uri.queryParameters['issuer'] ?? '';
    String accountName = pathSegment;

    if (pathSegment.contains(':')) {
      final parts = pathSegment.split(':');
      if (issuer.isEmpty) {
        issuer = parts[0].trim();
      }
      accountName = parts.sublist(1).join(':').trim();
    }

    final secret = uri.queryParameters['secret'] ?? '';
    if (secret.isEmpty) {
      throw ArgumentError('Missing secret parameter in otpauth URI');
    }

    final algorithm = uri.queryParameters['algorithm'] ?? 'SHA1';
    final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
    final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;

    return TotpParams(
      issuer: issuer,
      accountName: accountName,
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }
}
