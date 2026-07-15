import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../crypto/crypto.dart';
import '../crypto/srp.dart';

/// Exception thrown when registration fails because the email is already registered.
class DuplicateEmailException implements Exception {
  /// The descriptive error message associated with this duplicate email occurrence.
  final String message;

  /// Creates a [DuplicateEmailException] with the specified [message].
  DuplicateEmailException(this.message);

  @override
  String toString() => message;
}

/// Client for communicating with the NestJS authentication microservice.
class AuthClient {
  /// The root URL of the authentication backend service.
  final String baseUrl;
  final http.Client _httpClient;
  final VaultCrypto _crypto;

  /// Creates a new [AuthClient].
  AuthClient({
    required this.baseUrl,
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _crypto = VaultCrypto();

  /// Registers a user using the SRP-6a registration protocol.
  ///
  /// Computes the verifier `v = g^x mod N` client-side from the [email] and [password],
  /// then posts the [email], the random salt (hex), and the computed verifier (hex).
  ///
  /// Returns the JWT session token issued by the server immediately after
  /// successful registration, so the caller can set the active session before
  /// making any further authenticated API calls (e.g. POST /sync/vault-key).
  ///
  /// Security invariant: The password never leaves the client device in plaintext.
  Future<String> register(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      throw ArgumentError('Email and password must not be empty');
    }

    final salt = _crypto.generateRandomBytes(16);
    final passwordBytes = utf8.encode(password);

    try {
      final verifier = await SrpClient.calculateVerifier(email, passwordBytes, salt);

      final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final verifierHex = verifier.toRadixString(16);

      final url = Uri.parse('$baseUrl/auth/register');
      final response = await _httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': email,
          'salt': saltHex,
          'verifier': verifierHex,
        }),
      );

      if (response.statusCode == 409) {
        throw DuplicateEmailException('Username already exists');
      } else if (response.statusCode != 201 && response.statusCode != 200) {
        throw Exception('Registration failed with status code: ${response.statusCode}');
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      final token = body['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Registration succeeded but server returned no session token');
      }
      return token;
    } finally {
      // Clear sensitive memory bytes immediately
      for (var i = 0; i < passwordBytes.length; i++) {
        passwordBytes[i] = 0;
      }
    }
  }

  /// Authenticates a user using the SRP-6a login protocol.
  ///
  /// Security invariant: The password never leaves the client device in plaintext.
  Future<String> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      throw ArgumentError('Email and password must not be empty');
    }

    final passwordBytes = utf8.encode(password);
    final aRandomBytes = _crypto.generateRandomBytes(32);

    try {
      // 1. Generate client ephemeral values A and secret a
      final ephemeral = SrpClient.generateClientEphemeral(aRandomBytes);
      final aHex = ephemeral.publicValue.toRadixString(16);

      // 2. Post to login step 1
      final step1Url = Uri.parse('$baseUrl/auth/login/step1');
      final step1Response = await _httpClient.post(
        step1Url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': email,
          'A': aHex,
        }),
      );

      if (step1Response.statusCode != 200) {
        throw Exception('Incorrect username or password');
      }

      final step1Data = json.decode(step1Response.body) as Map<String, dynamic>;
      final challengeId = step1Data['challengeId'] as String;
      final saltHex = step1Data['salt'] as String;
      final bHex = step1Data['B'] as String;

      final salt = hexToBytes(saltHex);
      final bVal = BigInt.parse(bHex, radix: 16);

      // 3. Compute client session key and client evidence M1
      final session = await SrpClient.calculateClientSession(
        username: email,
        salt: salt,
        a: ephemeral.secret,
        A: ephemeral.publicValue,
        B: bVal,
        masterKey: passwordBytes,
      );

      final m1Hex = session.clientEvidence.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // 4. Post to login step 2
      final step2Url = Uri.parse('$baseUrl/auth/login/step2');
      final step2Response = await _httpClient.post(
        step2Url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'challengeId': challengeId,
          'M1': m1Hex,
        }),
      );

      if (step2Response.statusCode != 200) {
        throw Exception('Incorrect username or password');
      }

      final step2Data = json.decode(step2Response.body) as Map<String, dynamic>;

      // Verify server evidence
      final serverEvidenceHex = step2Data['serverEvidence'] as String;
      final expectedServerEvidenceHex = session.expectedServerEvidence.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      if (serverEvidenceHex.toLowerCase() != expectedServerEvidenceHex.toLowerCase()) {
        throw Exception('Server authentication proof failed');
      }

      final token = step2Data['token'] as String;
      return token;
    } finally {
      // Clear sensitive memory bytes immediately
      for (var i = 0; i < passwordBytes.length; i++) {
        passwordBytes[i] = 0;
      }
      for (var i = 0; i < aRandomBytes.length; i++) {
        aRandomBytes[i] = 0;
      }
    }
  }

  /// Converts a hexadecimal string to a list of bytes.
  List<int> hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    final len = hex.length ~/ 2;
    final bytes = Uint8List(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

