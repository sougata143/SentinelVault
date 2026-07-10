import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../crypto/crypto.dart';
import '../crypto/srp.dart';

/// Exception thrown when registration fails because the email is already registered.
class DuplicateEmailException implements Exception {
  final String message;
  DuplicateEmailException(this.message);

  @override
  String toString() => message;
}

/// Client for communicating with the NestJS authentication microservice.
class AuthClient {
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
  /// Security invariant: The password never leaves the client device in plaintext.
  Future<void> register(String email, String password) async {
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
    } finally {
      // Clear sensitive memory bytes immediately
      for (var i = 0; i < passwordBytes.length; i++) {
        passwordBytes[i] = 0;
      }
    }
  }
}
