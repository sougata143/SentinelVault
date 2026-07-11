import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'native_crypto_bridge.dart';
import 'native_crypto_bridge_selector.dart';

/// Client-side Secure Remote Password (SRP-6a) authentication.
///
/// Implements RFC 5054 2048-bit prime group calculations.
/// Security invariant: Neither the master password nor the derived Master Key
/// is ever transmitted to the server in plaintext.
class SrpClient {
  static final NativeCryptoBridge _bridge = NativeCryptoBridgeImpl();

  /// The 2048-bit prime N from RFC 5054 (hexadecimal).
  static final BigInt N = BigInt.parse(
    'AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC332F683B94471B'
    'A25CEB5F15DE38B4341168461CCBA0140F00D0160AFFA93DD2C85E247E674003'
    '79E0957D0502438DF02B22B647CA55F2A3841D39634992644265EEBEC4D20A16'
    'C5F3528A6D15E4407B18E06A53ED9027D9B420C21C313E1B2749591A9B65438A'
    '2566CCC4465B2035F121210850D6955DFEB4CD0EE5460E58F69646FA5E4B4957'
    'B733B9B47E53B026BE6395EE1B24E7985474D5409605553E4774B819EF66E2E1'
    '9C898394EAEEDC4C7E9C4CC295F8CCE8CC991666CB29A51F2231BC7FF2FB81C7'
    '89FE2CA0B83EAD80A3A059B51E13D667793B9F2EA2F29A58814D7964E94EA25D',
    radix: 16,
  );

  /// The generator g = 2.
  static final BigInt g = BigInt.from(2);

  /// The standard SRP-6a multiplier k = H(N, g).
  /// For the 2048-bit group, we precompute this or compute it at runtime.
  /// Standard SRP-6a dictates k = 3 or H(N, g). We will use H(N, g) calculated dynamically.
  static BigInt? _kCache;

  /// Retrieves the multiplier k.
  static Future<BigInt> getMultiplierK() async {
    if (_kCache != null) return _kCache!;
    final nBytes = bigIntToBytesPadded(N, 256);
    final gBytes = bigIntToBytesPadded(g, 256);
    final combined = Uint8List(nBytes.length + gBytes.length);
    combined.setRange(0, nBytes.length, nBytes);
    combined.setRange(nBytes.length, combined.length, gBytes);
    final hash = await sha256Hash(combined);
    _kCache = bytesToBigInt(hash);
    return _kCache!;
  }

  /// Calculates the private key x:
  /// `x = H(salt, H(username + ":" + masterKeyHex))`
  ///
  /// Security invariant: The masterKey is the derived Argon2id output.
  static Future<BigInt> calculateX(
    String username,
    List<int> masterKey,
    List<int> salt,
  ) async {
    final xBytes = await _bridge.srpCalculateX(
      username: username,
      masterKey: masterKey,
      salt: salt,
    );
    return bytesToBigInt(xBytes);
  }

  /// Computes the verifier v = g^x mod N.
  ///
  /// Security invariant: The verifier is safe to store on the server.
  static Future<BigInt> calculateVerifier(
    String username,
    List<int> masterKey,
    List<int> salt,
  ) async {
    final vBytes = await _bridge.srpCalculateVerifier(
      username: username,
      masterKey: masterKey,
      salt: salt,
    );
    return bytesToBigInt(vBytes);
  }

  /// Generates client ephemeral secret [a] and public [A].
  ///
  /// Security invariant: Ephemeral secret [a] must be cryptographically secure and kept in memory.
  static SrpEphemeral generateClientEphemeral(List<int> secureRandomBytes) {
    final results = _bridge.srpGenerateClientEphemeral(
      secureRandomBytes: secureRandomBytes,
    );
    return SrpEphemeral(
      secret: bytesToBigInt(results[0]),
      publicValue: bytesToBigInt(results[1]),
    );
  }

  /// Computes the client session key K and evidence M1.
  ///
  /// Security invariant: Returns the derived shared session key and evidence verification bytes.
  static Future<SrpSession> calculateClientSession({
    required String username,
    required List<int> salt,
    required BigInt a,
    required BigInt A,
    required BigInt B,
    required List<int> masterKey,
  }) async {
    final aBytes = bigIntToBytesPadded(a, 256);
    final aPubBytes = bigIntToBytesPadded(A, 256);
    final bPubBytes = bigIntToBytesPadded(B, 256);

    final results = await _bridge.srpCalculateClientSession(
      username: username,
      salt: salt,
      a: aBytes,
      A: aPubBytes,
      B: bPubBytes,
      masterKey: masterKey,
    );

    return SrpSession(
      sessionKey: results[0],
      clientEvidence: results[1],
      expectedServerEvidence: results[2],
    );
  }

  // Helper primitives

  /// Hashes a byte list using SHA-256.
  static Future<Uint8List> sha256Hash(List<int> bytes) async {
    final hash = await Sha256().hash(bytes);
    return Uint8List.fromList(hash.bytes);
  }

  /// Converts a [BigInt] to a big-endian byte array padded to [length].
  static Uint8List bigIntToBytesPadded(BigInt number, int length) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    final rawBytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < rawBytes.length; i++) {
      rawBytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (rawBytes.length == length) {
      return rawBytes;
    }
    if (rawBytes.length > length) {
      return Uint8List.sublistView(rawBytes, rawBytes.length - length);
    }
    final padded = Uint8List(length);
    padded.setRange(length - rawBytes.length, length, rawBytes);
    return padded;
  }

  /// Converts a byte array to a positive [BigInt].
  static BigInt bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}

/// Represents the public and private ephemeral key values.
class SrpEphemeral {
  /// The ephemeral secret exponent (a or b).
  final BigInt secret;
  /// The public ephemeral value (A or B).
  final BigInt publicValue;

  /// Creates a new [SrpEphemeral].
  SrpEphemeral({required this.secret, required this.publicValue});
}

/// Represents the session key and evidence parameters.
class SrpSession {
  /// The derived shared session key K.
  final List<int> sessionKey;
  /// The client evidence M1.
  final List<int> clientEvidence;
  /// The expected server evidence M2.
  final List<int> expectedServerEvidence;

  /// Creates a new [SrpSession].
  SrpSession({
    required this.sessionKey,
    required this.clientEvidence,
    required this.expectedServerEvidence,
  });
}
