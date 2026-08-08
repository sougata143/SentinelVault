import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('LoginFields Password Rotation & Rollback History', () {
    test('rotatePassword archives current password to history and sets new password', () {
      final initialFields = LoginFields(
        username: 'user@example.com',
        password: const ConcealedValue.plain('OldPass123!'),
        urls: ['https://example.com'],
        otpSecret: const ConcealedValue.plain(''),
        passwordHistory: [],
      );

      final rotatedFields = initialFields.rotatePassword(newPassword: 'NewPass456!');

      expect(rotatedFields.password.plaintext, equals('NewPass456!'));
      expect(rotatedFields.passwordHistory.length, equals(1));
      expect(rotatedFields.passwordHistory.first.password.plaintext, equals('OldPass123!'));
      expect(rotatedFields.lastRotatedAt, isNotNull);
    });

    test('rollbackPassword restores previous password from history', () {
      final initialFields = LoginFields(
        username: 'user@example.com',
        password: const ConcealedValue.plain('OldPass123!'),
        urls: ['https://example.com'],
        otpSecret: const ConcealedValue.plain(''),
        passwordHistory: [],
      );

      final rotatedFields = initialFields.rotatePassword(newPassword: 'NewPass456!');
      expect(rotatedFields.password.plaintext, equals('NewPass456!'));

      final rolledBackFields = rotatedFields.rollbackPassword();
      expect(rolledBackFields.password.plaintext, equals('OldPass123!'));
      expect(rolledBackFields.passwordHistory.length, equals(0));
    });

    test('caps password history at maximum 5 entries', () {
      var fields = LoginFields(
        username: 'user@example.com',
        password: const ConcealedValue.plain('Pass0'),
        urls: [],
        otpSecret: const ConcealedValue.plain(''),
        passwordHistory: [],
      );

      for (var i = 1; i <= 7; i++) {
        fields = fields.rotatePassword(newPassword: 'Pass$i');
      }

      expect(fields.password.plaintext, equals('Pass7'));
      expect(fields.passwordHistory.length, equals(5));
      expect(fields.passwordHistory.first.password.plaintext, equals('Pass6'));
      expect(fields.passwordHistory.last.password.plaintext, equals('Pass2'));
    });

    test('isRotationDue checks interval correctly', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 95));
      final recentDate = DateTime.now().subtract(const Duration(days: 10));

      final overdueFields = LoginFields(
        username: 'user@example.com',
        password: const ConcealedValue.plain('Pass'),
        urls: [],
        otpSecret: const ConcealedValue.plain(''),
        passwordHistory: [],
        lastRotatedAt: pastDate,
        rotationReminderDays: 90,
      );

      final freshFields = LoginFields(
        username: 'user@example.com',
        password: const ConcealedValue.plain('Pass'),
        urls: [],
        otpSecret: const ConcealedValue.plain(''),
        passwordHistory: [],
        lastRotatedAt: recentDate,
        rotationReminderDays: 90,
      );

      expect(overdueFields.isRotationDue(), isTrue);
      expect(freshFields.isRotationDue(), isFalse);
    });
  });
}
