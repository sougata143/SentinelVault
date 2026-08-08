import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('PatHelper Token Format & Scope Verification Tests', () {
    test('1. Validates token format matching pat_sv_live_<32_hex_chars>', () {
      const validToken = 'pat_sv_live_a1b2c3d4e5f60718293a4b5c6d7e8f90';
      const invalidPrefix = 'pat_invalid_a1b2c3d4e5f60718293a4b5c6d7e8f90';
      const shortToken = 'pat_sv_live_12345';

      expect(PatHelper.isValidPatFormat(validToken), isTrue);
      expect(PatHelper.isValidPatFormat(invalidPrefix), isFalse);
      expect(PatHelper.isValidPatFormat(shortToken), isFalse);
    });

    test('2. Extracts display prefix safely', () {
      const token = 'pat_sv_live_a1b2c3d4e5f60718293a4b5c6d7e8f90';
      expect(PatHelper.extractDisplayPrefix(token), equals('pat_sv_live_a1b2...'));
    });

    test('3. Verifies scope checking logic', () {
      const scopes = ['vault:read', 'sharing:read'];

      expect(PatHelper.hasScope(requiredScope: 'vault:read', grantedScopes: scopes), isTrue);
      expect(PatHelper.hasScope(requiredScope: 'vault:write', grantedScopes: scopes), isFalse);

      const adminScopes = ['admin:*'];
      expect(PatHelper.hasScope(requiredScope: 'vault:write', grantedScopes: adminScopes), isTrue);
    });
  });
}
