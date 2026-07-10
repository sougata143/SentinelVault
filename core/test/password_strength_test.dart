import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('PasswordAnalyzer zxcvbn-style Tests', () {
    test('1. Empty password handles gracefully', () {
      final result = PasswordAnalyzer.analyze('');
      expect(result.score, equals(0));
      expect(result.estimatedCrackTime, equals('instant'));
      expect(result.matchedPatterns, isEmpty);
      expect(result.suggestions, contains('Enter a password'));
    });

    test('2. Common passwords/keyboard patterns are scored as weak (0-1)', () {
      final weakPasswords = [
        '123456',
        'password',
        'qwerty',
        'admin123',
        'monkey',
      ];

      for (final pwd in weakPasswords) {
        final result = PasswordAnalyzer.analyze(pwd);
        expect(result.score, lessThanOrEqualTo(1), reason: 'Password "$pwd" should be weak');
        expect(result.matchedPatterns, isNotEmpty);
      }
    });

    test('3. Matched patterns are correctly extracted', () {
      // Keyboard sequence
      final result1 = PasswordAnalyzer.analyze('plmkoijn');
      expect(result1.matchedPatterns, contains('spatial'));

      // Repeating pattern
      final result2 = PasswordAnalyzer.analyze('aaaaaa');
      expect(result2.matchedPatterns, contains('repeat'));

      // Dictionary word
      final result3 = PasswordAnalyzer.analyze('computer');
      expect(result3.matchedPatterns, contains('dictionary'));
    });

    test('4. Long passphrases and complex passwords score strong (3-4)', () {
      final strongPasswords = [
        'correcthorsebatterystaple', // passphrase
        r'9#jK!2$mNqP7*zWb', // high entropy random
        'sentinel-vault-security-key-2026', // long passphrase
      ];

      for (final pwd in strongPasswords) {
        final result = PasswordAnalyzer.analyze(pwd);
        expect(result.score, greaterThanOrEqualTo(3), reason: 'Password "$pwd" should be strong');
        expect(result.suggestions, isEmpty); // strong passwords usually have no suggestions
      }
    });

    test('5. Penalizes passwords containing user-specific inputs', () {
      const username = 'sougataroy';
      const email = 'sougata@sentinelvault.com';
      final inputs = [username, email];

      // "sougataroy123" should be weak because it contains the username
      final result = PasswordAnalyzer.analyze('sougataroy123', userInputs: inputs);
      expect(result.score, lessThan(2));
      expect(result.matchedPatterns, contains('dictionary'));
    });
  });
}
