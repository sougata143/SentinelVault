import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('EmailScanner Tests', () {
    test('1. Parses and validates a known-good authentic email', () {
      final cleanEmail = '''
From: "PayPal Support" <support@paypal.com>
Reply-To: <support@paypal.com>
Subject: Your monthly statement is ready
Authentication-Results: mx.google.com;
       spf=pass (google.com: domain of support@paypal.com designates 173.224.160.12 as permitted sender) smtp.mailfrom=support@paypal.com;
       dkim=pass header.i=@paypal.com;
       dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=paypal.com

Dear Customer,
Your monthly account statement is now available to download. Please log in to your dashboard to review it.
Thank you for using our services.
''';

      final result = EmailScanner.scan(cleanEmail);

      expect(result.senderEmail, equals('support@paypal.com'));
      expect(result.senderDomain, equals('paypal.com'));
      expect(result.displayName, equals('PayPal Support'));
      expect(result.replyToEmail, equals('support@paypal.com'));
      
      expect(result.spf, equals('pass'));
      expect(result.dkim, equals('pass'));
      expect(result.dmarc, equals('pass'));

      expect(result.isSenderSpoofed, isFalse);
      expect(result.isReplyToMismatch, isFalse);
      expect(result.urgencyLanguageDetected, isFalse);
      expect(result.extractedUrls, isEmpty);
      expect(result.isMalicious, isFalse);
    });

    test('2. Detects spoofing and phishing markers in a malicious email', () {
      final maliciousEmail = '''
From: "PayPal Account Security" <verify@paypa1-support-billing.net>
Reply-To: <hacker-inbox@gmail.com>
Subject: SECURITY ALERT: Verify immediately!
Authentication-Results: mx.google.com;
       spf=fail (google.com: domain of verify@paypa1-support-billing.net does not designate 203.0.113.50 as permitted sender);
       dkim=fail header.i=@paypa1-support-billing.net;
       dmarc=fail header.from=paypa1-support-billing.net
Received-SPF: fail (google.com: domain of verify@paypa1-support-billing.net designates 203.0.113.50 as permitted sender)

Urgent Security Alert: Your account has been suspended due to unauthorized access.
You must verify immediately or your account will be suspended permanently.
Click here to confirm your identity: http://192.168.1.1/login
''';

      final result = EmailScanner.scan(maliciousEmail);

      expect(result.senderEmail, equals('verify@paypa1-support-billing.net'));
      expect(result.senderDomain, equals('paypa1-support-billing.net'));
      expect(result.displayName, equals('PayPal Account Security'));
      expect(result.replyToEmail, equals('hacker-inbox@gmail.com'));
      expect(result.replyToDomain, equals('gmail.com'));

      // Auth failures
      expect(result.spf, equals('fail'));
      expect(result.dkim, equals('fail'));
      expect(result.dmarc, equals('fail'));

      // Heuristic alerts
      expect(result.isSenderSpoofed, isTrue, reason: 'PayPal display name vs paypa1-support-billing.net domain');
      expect(result.isReplyToMismatch, isTrue, reason: 'Reply-To domain is gmail.com but From domain is paypa1-support-billing.net');
      expect(result.urgencyLanguageDetected, isTrue, reason: 'Contains verify immediately & account suspended');

      // Embedded URL checks
      expect(result.extractedUrls, contains('http://192.168.1.1/login'));
      expect(result.urlScanResults.first.isMalicious, isTrue, reason: 'Embedded URL uses an IP literal');

      expect(result.isMalicious, isTrue);
    });
  });
}
