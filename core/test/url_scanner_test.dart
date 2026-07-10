import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('UrlScanner Local Heuristics Tests', () {
    test('1. Extracts domains correctly', () {
      expect(UrlScanner.extractDomain('https://google.com/search?q=123'), equals('google.com'));
      expect(UrlScanner.extractDomain('http://192.168.1.1:8080/index.html'), equals('192.168.1.1'));
      expect(UrlScanner.extractDomain('github.com/trending'), equals('github.com'));
      expect(UrlScanner.extractDomain('  https://MY-DOMAIN.com/  '), equals('my-domain.com'));
    });

    test('2. Detects punycode / homoglyph domains', () {
      // 'аpple.com' where 'а' is Cyrillic small letter a (U+0430)
      final homoglyphUrl = 'https://\u0430pple.com';
      final result1 = UrlScanner.scanLocal(homoglyphUrl);
      expect(result1.isMalicious, isTrue);
      expect(result1.detectedHeuristics, contains('punycode_or_homoglyph'));

      // Real punycode representation
      final punycodeUrl = 'https://xn--pple-43d.com';
      final result2 = UrlScanner.scanLocal(punycodeUrl);
      expect(result2.isMalicious, isTrue);
      expect(result2.detectedHeuristics, contains('punycode_or_homoglyph'));
    });

    test('3. Detects IP-literal hosts', () {
      final ipv4Url = 'http://192.168.1.1/login';
      final result1 = UrlScanner.scanLocal(ipv4Url);
      expect(result1.isMalicious, isTrue);
      expect(result1.detectedHeuristics, contains('ip_literal'));

      final ipv6Url = 'http://[2001:db8::1]/index.php';
      final result2 = UrlScanner.scanLocal(ipv6Url);
      expect(result2.isMalicious, isTrue);
      expect(result2.detectedHeuristics, contains('ip_literal'));
    });

    test('4. Detects excessive subdomains', () {
      final maliciousSubdomainUrl = 'https://paypal.com.accounts.verify.signin.login-support.net/login';
      final result = UrlScanner.scanLocal(maliciousSubdomainUrl);
      expect(result.isMalicious, isTrue);
      expect(result.detectedHeuristics, contains('excessive_subdomains'));
    });

    test('5. Detects suspicious TLDs', () {
      final suspiciousTldUrl = 'https://my-secure-bank.xyz';
      final result = UrlScanner.scanLocal(suspiciousTldUrl);
      expect(result.isMalicious, isTrue);
      expect(result.detectedHeuristics, contains('suspicious_tld'));
    });

    test('6. Detects URL shorteners', () {
      final shortUrl = 'https://bit.ly/3g9k2L';
      final result = UrlScanner.scanLocal(shortUrl);
      expect(result.isMalicious, isTrue);
      expect(result.detectedHeuristics, contains('url_shortener'));
    });

    test('7. Safe domains pass with NO false positives', () {
      final safeUrls = [
        'https://google.com',
        'https://github.com/trending',
        'https://flutter.dev',
        'https://amazon.co.uk',
        'https://wikipedia.org/wiki/Main_Page',
      ];

      for (final url in safeUrls) {
        final result = UrlScanner.scanLocal(url);
        expect(result.isMalicious, isFalse, reason: 'URL "$url" should be marked safe');
        expect(result.detectedHeuristics, isEmpty);
      }
    });
  });
}
