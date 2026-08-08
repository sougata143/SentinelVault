import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../crypto/crypto.dart';

/// PKCE challenge pair for secure OpenID Connect OAuth2 authorization code flows.
class PkceChallengePair {
  /// High-entropy random code verifier string (43 to 128 chars).
  final String codeVerifier;
  /// Base64URL-encoded SHA-256 hash of [codeVerifier].
  final String codeChallenge;
  /// Challenge method (always 'S256').
  final String codeChallengeMethod;

  /// Creates a new [PkceChallengePair] instance.
  const PkceChallengePair({
    required this.codeVerifier,
    required this.codeChallenge,
    this.codeChallengeMethod = 'S256',
  });
}

/// Helper utilities for client-side SSO (OIDC / SAML) authentication flows.
class SsoAuthHelper {
  /// Generates a cryptographically secure PKCE code verifier and SHA-256 challenge.
  static PkceChallengePair generatePkceChallenge(VaultCrypto crypto) {
    final verifierBytes = crypto.generateRandomBytes(32);
    final codeVerifier = base64Url.encode(verifierBytes).replaceAll('=', '');

    final digest = sha256.convert(utf8.encode(codeVerifier));
    final codeChallenge = base64Url.encode(digest.bytes).replaceAll('=', '');

    return PkceChallengePair(
      codeVerifier: codeVerifier,
      codeChallenge: codeChallenge,
    );
  }

  /// Extracts domain from an email address (e.g. `alice@acme.corp` -> `@acme.corp`).
  static String? extractDomainFromEmail(String email) {
    final parts = email.trim().toLowerCase().split('@');
    if (parts.length == 2 && parts[1].isNotEmpty) {
      return '@${parts[1]}';
    }
    return null;
  }
}
