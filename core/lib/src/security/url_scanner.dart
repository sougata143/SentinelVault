import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents the results of a three-layer URL scan.
class UrlScanResult {
  /// The scanned URL.
  final String url;

  /// The domain extracted from the URL.
  final String domain;

  /// Flags indicating which local heuristics triggered.
  final List<String> detectedHeuristics;

  /// Verdict from the reputation lookup ('safe', 'malicious', 'unknown', or 'unreachable').
  final String reputationVerdict;

  /// Plain-English explanation of why this URL is safe or risky.
  final String aiExplanation;

  /// Indicates if the URL is flagged as malicious (by either heuristics or reputation).
  final bool isMalicious;

  /// Creates a new [UrlScanResult].
  UrlScanResult({
    required this.url,
    required this.domain,
    required this.detectedHeuristics,
    required this.reputationVerdict,
    required this.aiExplanation,
    required this.isMalicious,
  });

  /// Converts the scan result to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'domain': domain,
      'detected_heuristics': detectedHeuristics,
      'reputation_verdict': reputationVerdict,
      'ai_explanation': aiExplanation,
      'is_malicious': isMalicious,
    };
  }
}

/// Provides heuristic checks and coordinates reputation/AI scans for URLs.
class UrlScanner {
  static final RegExp _ipv4Regex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  static final RegExp _ipv6Regex = RegExp(r'^\[?[0-9a-fA-F:]+\]?$');

  static const _suspiciousTlds = {
    'xyz', 'top', 'fit', 'link', 'click', 'work', 'zip', 'mov', 'cc', 'bit', 'online', 'club', 'download'
  };

  static const _urlShorteners = {
    'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'is.gd', 'buff.ly', 'sh.rt', 'rebrand.ly', 'tiny.cc'
  };

  /// Extracts the clean host/domain from a URL string.
  static String extractDomain(String urlString) {
    var cleanUrl = urlString.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    try {
      final uri = Uri.parse(cleanUrl);
      return uri.host.toLowerCase();
    } catch (_) {
      // Fallback manual parser if Uri fails
      var host = cleanUrl;
      if (host.contains('://')) {
        host = host.split('://')[1];
      }
      host = host.split('/')[0];
      host = host.split('?')[0];
      host = host.split(':')[0];
      return host.toLowerCase();
    }
  }

  /// Layer 1: Evaluates a URL entirely locally using heuristics.
  static List<String> checkHeuristics(String urlString, String domain) {
    final flags = <String>[];

    // 1. IP-literal check
    if (_ipv4Regex.hasMatch(domain) || (domain.contains(':') && _ipv6Regex.hasMatch(domain))) {
      flags.add('ip_literal');
    }

    // 2. Punycode / Homoglyph check
    final isPunycode = domain.startsWith('xn--');
    final hasNonAscii = domain.codeUnits.any((c) => c > 127) || urlString.codeUnits.any((c) => c > 127);
    final hasPercent = domain.contains('%'); // Uri.parse may percent-encode unicode hosts
    if (isPunycode || hasNonAscii || hasPercent) {
      flags.add('punycode_or_homoglyph');
    }

    // 3. Excessive subdomain nesting (more than 3 subdomains)
    final parts = domain.split('.');
    if (parts.length > 4) {
      flags.add('excessive_subdomains');
    }

    // 4. Suspicious TLD
    if (parts.isNotEmpty) {
      final tld = parts.last;
      if (_suspiciousTlds.contains(tld)) {
        flags.add('suspicious_tld');
      }
    }

    // 5. URL shorteners
    if (_urlShorteners.contains(domain)) {
      flags.add('url_shortener');
    }

    return flags;
  }

  /// Scans a URL locally (Layer 1 heuristics only) returning a fast, offline result.
  static UrlScanResult scanLocal(String urlString) {
    final domain = extractDomain(urlString);
    final heuristics = checkHeuristics(urlString, domain);
    final isMalicious = heuristics.isNotEmpty;

    return UrlScanResult(
      url: urlString,
      domain: domain,
      detectedHeuristics: heuristics,
      reputationVerdict: 'unknown',
      aiExplanation: isMalicious 
          ? 'Flagged locally due to security heuristics: ${heuristics.join(", ")}.' 
          : 'Heuristic check passed. No issues detected locally.',
      isMalicious: isMalicious,
    );
  }

  /// Layer 2 & 3: Performs a full online scan using the reputation backend and AI explanation.
  /// 
  /// Falls back gracefully to heuristic-only mode if the backend service is unreachable.
  static Future<UrlScanResult> scanOnline(
    String urlString, {
    String backendUrl = 'http://localhost:3003',
  }) async {
    final domain = extractDomain(urlString);
    final heuristics = checkHeuristics(urlString, domain);
    final isLocalMalicious = heuristics.isNotEmpty;

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/security-analysis/scan-url'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'domain': domain,
          'heuristics': heuristics,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final reputationVerdict = body['reputationVerdict'] as String? ?? 'unknown';
        final aiExplanation = body['aiExplanation'] as String? ?? 'No explanation provided.';
        final isServerMalicious = body['isMalicious'] as bool? ?? false;

        return UrlScanResult(
          url: urlString,
          domain: domain,
          detectedHeuristics: heuristics,
          reputationVerdict: reputationVerdict,
          aiExplanation: aiExplanation,
          isMalicious: isLocalMalicious || isServerMalicious || reputationVerdict == 'malicious',
        );
      }
    } catch (_) {
      // Fail safe: fall back to local heuristic-only verdict
    }

    return UrlScanResult(
      url: urlString,
      domain: domain,
      detectedHeuristics: heuristics,
      reputationVerdict: 'unreachable',
      aiExplanation: 'Reputation lookup failed (service unreachable). '
          '${isLocalMalicious ? "Flagged locally due to heuristics: ${heuristics.join(', ')}." : "Local heuristics passed."}',
      isMalicious: isLocalMalicious,
    );
  }
}
