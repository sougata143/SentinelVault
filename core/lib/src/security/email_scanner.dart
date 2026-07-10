import 'url_scanner.dart';

/// Represents the structured result of an email phishing analysis.
class EmailScanResult {
  /// The sender's email address parsed from the From header.
  final String senderEmail;

  /// The domain of the sender's email.
  final String senderDomain;

  /// The sender's display name parsed from the From header.
  final String displayName;

  /// The Reply-To email address if present.
  final String replyToEmail;

  /// The domain of the Reply-To email.
  final String replyToDomain;

  /// SPF result ('pass', 'fail', or 'none').
  final String spf;

  /// DKIM result ('pass', 'fail', or 'none').
  final String dkim;

  /// DMARC result ('pass', 'fail', or 'none').
  final String dmarc;

  /// Indicates if a brand display name mismatch was detected (Sender Spoofing).
  final bool isSenderSpoofed;

  /// Indicates if Reply-To domain differs from From domain.
  final bool isReplyToMismatch;

  /// Indicates if urgency/pressure language was detected locally.
  final bool urgencyLanguageDetected;

  /// List of raw URLs extracted from the body.
  final List<String> extractedUrls;

  /// Local scan results for each extracted URL.
  final List<UrlScanResult> urlScanResults;

  /// Final verdict: whether the email is flagged as phishing/malicious.
  final bool isMalicious;

  /// Creates a new [EmailScanResult].
  EmailScanResult({
    required this.senderEmail,
    required this.senderDomain,
    required this.displayName,
    required this.replyToEmail,
    required this.replyToDomain,
    required this.spf,
    required this.dkim,
    required this.dmarc,
    required this.isSenderSpoofed,
    required this.isReplyToMismatch,
    required this.urgencyLanguageDetected,
    required this.extractedUrls,
    required this.urlScanResults,
    required this.isMalicious,
  });

  /// Converts the result to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'sender_email': senderEmail,
      'sender_domain': senderDomain,
      'display_name': displayName,
      'reply_to_email': replyToEmail,
      'reply_to_domain': replyToDomain,
      'spf': spf,
      'dkim': dkim,
      'dmarc': dmarc,
      'is_sender_spoofed': isSenderSpoofed,
      'is_reply_to_mismatch': isReplyToMismatch,
      'urgency_language_detected': urgencyLanguageDetected,
      'url_flags': urlScanResults.expand((r) => r.detectedHeuristics).toSet().toList(),
      'is_malicious': isMalicious,
    };
  }
}

/// Parses and checks email headers and bodies locally for security risks.
class EmailScanner {
  static final RegExp _urlRegex = RegExp(
    r'https?://[a-zA-Z0-9\-._~%!$&()*+,;=:@/]+',
    caseSensitive: false,
  );

  static const _brandDomains = {
    'paypal': ['paypal.com', 'paypal.co.uk'],
    'google': ['google.com', 'gmail.com', 'google.co.in'],
    'microsoft': ['microsoft.com', 'outlook.com', 'hotmail.com', 'live.com'],
    'netflix': ['netflix.com'],
    'apple': ['apple.com', 'icloud.com'],
    'amazon': ['amazon.com', 'amazon.co.uk', 'amazon.ca', 'amazon.de'],
    'github': ['github.com'],
    'chase': ['chase.com'],
    'bank of america': ['bankofamerica.com'],
  };

  static const _urgencyKeywords = [
    'verify immediately',
    'account suspended',
    'urgent action required',
    'security alert',
    'unauthorized access',
    'confirm your identity',
    'suspended immediately',
    'click below to restore',
    'action required',
    'confirm your password',
    'password reset required',
    'critical update',
  ];

  /// Parses a raw email string (headers + body) or just headers.
  static EmailScanResult scan(String rawInput) {
    // 1. Split headers from body (separated by double newlines)
    String headersPart = rawInput;
    String bodyPart = '';

    final separatorIndex = rawInput.indexOf('\n\n');
    final separatorIndexCarriage = rawInput.indexOf('\r\n\r\n');

    if (separatorIndexCarriage != -1) {
      headersPart = rawInput.substring(0, separatorIndexCarriage);
      bodyPart = rawInput.substring(separatorIndexCarriage + 4);
    } else if (separatorIndex != -1) {
      headersPart = rawInput.substring(0, separatorIndex);
      bodyPart = rawInput.substring(separatorIndex + 2);
    }

    // 2. Unfold and parse headers
    final headers = _parseHeaders(headersPart);

    // 3. Extract sender details (From)
    final fromHeader = headers['from']?.first ?? '';
    final parsedFrom = _parseEmailAddress(fromHeader);
    final senderEmail = parsedFrom['email'] ?? '';
    final displayName = parsedFrom['name'] ?? '';
    final senderDomain = senderEmail.contains('@') ? senderEmail.split('@').last.toLowerCase() : '';

    // 4. Extract Reply-To details
    final replyToHeader = headers['reply-to']?.first ?? '';
    final parsedReplyTo = _parseEmailAddress(replyToHeader);
    final replyToEmail = parsedReplyTo['email'] ?? '';
    final replyToDomain = replyToEmail.contains('@') ? replyToEmail.split('@').last.toLowerCase() : '';

    // 5. Extract SPF/DKIM/DMARC verdicts
    final authResults = headers['authentication-results'] ?? [];
    final receivedSpf = headers['received-spf'] ?? [];

    final spf = _extractAuthVerdict('spf', authResults, receivedSpf);
    final dkim = _extractAuthVerdict('dkim', authResults, []);
    final dmarc = _extractAuthVerdict('dmarc', authResults, []);

    // 6. Check sender brand spoofing
    var isSenderSpoofed = false;
    final nameLower = displayName.toLowerCase();
    for (final brand in _brandDomains.keys) {
      if (nameLower.contains(brand)) {
        final allowedDomains = _brandDomains[brand]!;
        if (senderDomain.isNotEmpty && !allowedDomains.any((d) => senderDomain == d || senderDomain.endsWith('.$d'))) {
          isSenderSpoofed = true;
          break;
        }
      }
    }

    // 7. Check Reply-To mismatch
    final isReplyToMismatch = replyToDomain.isNotEmpty && senderDomain.isNotEmpty && replyToDomain != senderDomain;

    // 8. Analyze body: Urgency Keywords
    final bodyLower = bodyPart.toLowerCase();
    final urgencyLanguageDetected = _urgencyKeywords.any((kw) => bodyLower.contains(kw));

    // 9. Analyze body: Extract and scan URLs
    final extractedUrls = _urlRegex.allMatches(bodyPart).map((m) => m.group(0)!).toSet().toList();
    final urlScanResults = extractedUrls.map((url) => UrlScanner.scanLocal(url)).toList();

    // 10. Compute final malicious verdict
    final hasAuthFailure = spf == 'fail' || dkim == 'fail' || dmarc == 'fail';
    final hasUrlThreat = urlScanResults.any((r) => r.isMalicious);
    final isMalicious = hasAuthFailure || isSenderSpoofed || isReplyToMismatch || hasUrlThreat;

    return EmailScanResult(
      senderEmail: senderEmail,
      senderDomain: senderDomain,
      displayName: displayName,
      replyToEmail: replyToEmail,
      replyToDomain: replyToDomain,
      spf: spf,
      dkim: dkim,
      dmarc: dmarc,
      isSenderSpoofed: isSenderSpoofed,
      isReplyToMismatch: isReplyToMismatch,
      urgencyLanguageDetected: urgencyLanguageDetected,
      extractedUrls: extractedUrls,
      urlScanResults: urlScanResults,
      isMalicious: isMalicious,
    );
  }

  /// Parses raw headers string into a folded key-value map.
  static Map<String, List<String>> _parseHeaders(String rawHeaders) {
    final Map<String, List<String>> parsed = {};
    final lines = rawHeaders.split(RegExp(r'\r?\n'));
    
    String? currentKey;
    String currentValue = '';

    for (final line in lines) {
      if (line.isEmpty) continue;

      // Check if this line is a continuation (starts with whitespace)
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (currentKey != null) {
          currentValue += ' ${line.trim()}';
        }
      } else {
        // Save previous header if any
        if (currentKey != null) {
          parsed.putIfAbsent(currentKey, () => []).add(currentValue);
        }

        // Parse new header
        final colonIndex = line.indexOf(':');
        if (colonIndex != -1) {
          currentKey = line.substring(0, colonIndex).trim().toLowerCase();
          currentValue = line.substring(colonIndex + 1).trim();
        } else {
          currentKey = null;
        }
      }
    }

    // Save final header
    if (currentKey != null) {
      parsed.putIfAbsent(currentKey, () => []).add(currentValue);
    }

    return parsed;
  }

  /// Parses "Display Name <email@domain.com>" or "email@domain.com"
  static Map<String, String> _parseEmailAddress(String headerValue) {
    final trimmed = headerValue.trim();
    if (trimmed.isEmpty) return {'name': '', 'email': ''};

    final bracketStart = trimmed.indexOf('<');
    final bracketEnd = trimmed.lastIndexOf('>');

    if (bracketStart != -1 && bracketEnd != -1 && bracketEnd > bracketStart) {
      final name = trimmed.substring(0, bracketStart).replaceAll('"', '').trim();
      final email = trimmed.substring(bracketStart + 1, bracketEnd).trim();
      return {'name': name, 'email': email};
    }

    return {'name': '', 'email': trimmed};
  }

  /// Extracts SPF/DKIM/DMARC verdict from Authentication-Results or Received-SPF headers.
  static String _extractAuthVerdict(String method, List<String> authResults, List<String> fallbackHeaders) {
    // 1. Look in Authentication-Results
    for (final header in authResults) {
      final matches = RegExp('$method\\s*=\\s*([a-zA-Z]+)', caseSensitive: false).firstMatch(header);
      if (matches != null) {
        final verdict = matches.group(1)!.toLowerCase();
        if (verdict == 'pass' || verdict == 'fail' || verdict == 'none' || verdict == 'softfail') {
          return verdict == 'softfail' ? 'fail' : verdict;
        }
      }
    }

    // 2. Look in Received-SPF (only for spf method)
    if (method == 'spf') {
      for (final header in fallbackHeaders) {
        final lower = header.toLowerCase();
        if (lower.startsWith('pass')) return 'pass';
        if (lower.startsWith('fail') || lower.startsWith('softfail')) return 'fail';
        if (lower.startsWith('none')) return 'none';
      }
    }

    return 'none';
  }
}
