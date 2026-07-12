import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Result of a k-anonymity HIBP password range check.
class PasswordBreachResult {
  /// The 5-character SHA-1 prefix that was sent to the HIBP API.
  /// Only this prefix leaves the device — never the full hash or password.
  final String prefix;

  /// Number of times this password appeared in known breach databases.
  /// A value of 0 means it was not found in any breach in the HIBP dataset.
  final int pwnedCount;

  /// Whether [pwnedCount] > 0.
  bool get isBreached => pwnedCount > 0;

  /// Creates a [PasswordBreachResult].
  const PasswordBreachResult({required this.prefix, required this.pwnedCount});
}

/// Result of an opted-in email breach lookup.
class EmailBreachResult {
  /// The service or site name where the breach occurred.
  final String breachName;

  /// The date the breach was reported (ISO 8601 date string).
  final String breachDate;

  /// Human-readable list of data types exposed (e.g. "Passwords", "Emails").
  final List<String> dataClasses;

  /// Creates an [EmailBreachResult].
  const EmailBreachResult({
    required this.breachName,
    required this.breachDate,
    required this.dataClasses,
  });

  /// Parses from HIBP JSON map.
  factory EmailBreachResult.fromJson(Map<String, dynamic> json) {
    return EmailBreachResult(
      breachName: (json['Name'] as String?) ?? 'Unknown',
      breachDate: (json['BreachDate'] as String?) ?? 'Unknown',
      dataClasses: List<String>.from(json['DataClasses'] as List? ?? []),
    );
  }

  /// Converts to a redacted JSON map safe to pass to AI insights layer.
  /// Contains only breach metadata — never the user's email or password.
  Map<String, dynamic> toRedactedJson() => {
        'breach_name': breachName,
        'breach_date': breachDate,
        'data_classes_exposed': dataClasses,
      };
}

/// Provides privacy-preserving breach checks against the Have I Been Pwned
/// (HIBP) API.
///
/// ## Security invariants:
/// - [checkPassword] sends **only** the first 5 hex characters of the SHA-1
///   hash of the password. The full hash and the plaintext password never
///   leave the device.
/// - [checkEmail] sends the raw email address to HIBP. This is an explicit
///   exception that **requires user opt-in** with a clear disclosure dialog
///   before this method is ever called. The caller (UI layer) is responsible
///   for enforcing that consent gate.
class BreachMonitor {
  final http.Client _client;

  static const _hibpPasswordRangeBase =
      'https://api.pwnedpasswords.com/range/';

  static const _hibpEmailBreachBase =
      'https://haveibeenpwned.com/api/v3/breachedaccount/';

  /// Creates a [BreachMonitor]. Inject a custom [http.Client] for testing.
  BreachMonitor({http.Client? client}) : _client = client ?? http.Client();

  /// Checks whether [password] has appeared in any known breach using the
  /// HIBP k-anonymity range API.
  ///
  /// Only the first 5 hex characters of `SHA-1(password)` are transmitted.
  /// The remaining suffix is matched locally against the returned list.
  ///
  /// Returns a [PasswordBreachResult] with the breach count (0 = not found).
  /// Throws [BreachCheckException] on network or parse errors.
  Future<PasswordBreachResult> checkPassword(String password) async {
    if (password.isEmpty) {
      return const PasswordBreachResult(prefix: '', pwnedCount: 0);
    }

    // 1. SHA-1 hash the password entirely on device.
    final bytes = utf8.encode(password);
    final fullHash = sha1.convert(bytes).toString().toUpperCase();

    // 2. Split into prefix (first 5 chars) and suffix (remaining 35 chars).
    //    Only the prefix ever leaves the device.
    final prefix = fullHash.substring(0, 5);
    final localSuffix = fullHash.substring(5);

    // 3. Query HIBP range endpoint with the 5-char prefix only.
    final uri = Uri.parse('$_hibpPasswordRangeBase$prefix');
    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          // Add-Padding reduces timing attacks by making all responses
          // the same size regardless of whether the prefix has matches.
          'Add-Padding': 'true',
        },
      );
    } on Exception catch (e) {
      throw BreachCheckException('Network error during password check: $e');
    }

    if (response.statusCode != 200) {
      throw BreachCheckException(
        'HIBP API returned status ${response.statusCode}',
      );
    }

    // 4. Parse response lines of format "SUFFIX:COUNT" and find our suffix.
    //    HIBP pads responses with zero-count entries — filter those out.
    int pwnedCount = 0;
    for (final line in response.body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length != 2) continue;

      final suffix = parts[0].toUpperCase();
      final count = int.tryParse(parts[1]) ?? 0;

      if (suffix == localSuffix && count > 0) {
        pwnedCount = count;
        break;
      }
    }

    return PasswordBreachResult(prefix: prefix, pwnedCount: pwnedCount);
  }

  /// Checks [email] for known breaches via the HIBP v3 API.
  ///
  /// **This method sends the raw email address to a third-party API.**
  /// It MUST only be called after the user has explicitly consented via the
  /// opt-in disclosure dialog. The [apiKey] is required by HIBP v3.
  ///
  /// Returns a list of [EmailBreachResult] containing only breach metadata
  /// (name, date, data classes) — never the email itself is stored.
  /// Returns an empty list if the email is not found in any breach.
  Future<List<EmailBreachResult>> checkEmail(
    String email,
    String apiKey,
  ) async {
    final uri = Uri.parse(
      '$_hibpEmailBreachBase${Uri.encodeComponent(email)}?truncateResponse=false',
    );

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'hibp-api-key': apiKey,
          'user-agent': 'SentinelVault-BreachMonitor',
        },
      );
    } on Exception catch (e) {
      throw BreachCheckException('Network error during email check: $e');
    }

    // 404 means no breaches found — this is the happy path.
    if (response.statusCode == 404) return [];

    if (response.statusCode == 401) {
      throw const BreachCheckException('Invalid HIBP API key.');
    }
    if (response.statusCode == 429) {
      throw const BreachCheckException('HIBP rate limit exceeded. Try again later.');
    }
    if (response.statusCode != 200) {
      throw BreachCheckException(
        'HIBP API returned status ${response.statusCode}',
      );
    }

    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .whereType<Map<String, dynamic>>()
        .map(EmailBreachResult.fromJson)
        .toList();
  }

  /// Releases resources held by the underlying HTTP client.
  void dispose() => _client.close();
}

/// Thrown when a breach check fails due to a network or API error.
class BreachCheckException implements Exception {
  /// Human-readable description of the failure.
  final String message;

  /// Creates a [BreachCheckException] with [message].
  const BreachCheckException(this.message);

  @override
  String toString() => 'BreachCheckException: $message';
}

/// Client to query the NestJS breach monitor endpoints.
class BackendBreachMonitor {
  /// The base URL of the breach monitor backend service.
  final String backendUrl;
  final http.Client _client;

  /// Creates a new [BackendBreachMonitor] client.
  BackendBreachMonitor({this.backendUrl = 'http://localhost:3003', http.Client? client})
      : _client = client ?? http.Client();

  /// Enrolls the given [email] and [emailHash] into the dark-web breach monitoring service.
  ///
  /// Security invariant: No raw password or vault data is ever sent to this backend endpoint.
  Future<void> optIn(String email, String emailHash) async {
    try {
      final response = await _client.post(
        Uri.parse('$backendUrl/breach-monitor/opt-in'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'emailHash': emailHash}),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to opt in: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to connect to breach monitor backend: $e');
    }
  }

  /// Removes the user represented by [emailHash] from the dark-web breach monitoring service.
  Future<void> optOut(String emailHash) async {
    try {
      final response = await _client.delete(
        Uri.parse('$backendUrl/breach-monitor/opt-out/$emailHash'),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to opt out: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to connect to breach monitor backend: $e');
    }
  }

  /// Queries the breach database for any known leaks related to the given [emailHash].
  ///
  /// Returns a map describing the breach findings.
  Future<Map<String, dynamic>> checkBreaches(String emailHash) async {
    try {
      final response = await _client.post(
        Uri.parse('$backendUrl/breach-monitor/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'emailHash': emailHash}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to check breaches: ${response.statusCode}');
    } catch (e) {
      throw Exception('Failed to connect to breach monitor backend: $e');
    }
  }

  /// Retrieves the current subscription/opt-in status for the given [emailHash].
  Future<Map<String, dynamic>> getStatus(String emailHash) async {
    try {
      final response = await _client.get(
        Uri.parse('$backendUrl/breach-monitor/status/$emailHash'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to get breach status: ${response.statusCode}');
    } catch (e) {
      throw Exception('Failed to connect to breach monitor backend: $e');
    }
  }
}

