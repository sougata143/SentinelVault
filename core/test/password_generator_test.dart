import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('PasswordGenerator', () {
    test('generates password of requested length', () {
      final pwd = PasswordGenerator.generate(length: 24);
      expect(pwd.length, equals(24));
    });

    test('includes uppercase, lowercase, numbers, symbols by default', () {
      final pwd = PasswordGenerator.generate(length: 32);
      expect(pwd.contains(RegExp(r'[A-Z]')), isTrue);
      expect(pwd.contains(RegExp(r'[a-z]')), isTrue);
      expect(pwd.contains(RegExp(r'[0-9]')), isTrue);
      expect(pwd.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]')), isTrue);
    });

    test('respects character class toggles', () {
      final pwd = PasswordGenerator.generate(
        length: 20,
        includeUppercase: false,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: false,
      );
      expect(pwd.contains(RegExp(r'[A-Z]')), isFalse);
      expect(pwd.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]')), isFalse);
      expect(pwd.contains(RegExp(r'[a-z]')), isTrue);
      expect(pwd.contains(RegExp(r'[0-9]')), isTrue);
    });

    test('clamps length bounds safely', () {
      final shortPwd = PasswordGenerator.generate(length: 2);
      expect(shortPwd.length, equals(4));

      final longPwd = PasswordGenerator.generate(length: 200);
      expect(longPwd.length, equals(128));
    });
  });
}
