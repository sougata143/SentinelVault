import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('Shamir Recovery Tests', () {
    late ShamirRecovery shamir;
    const testRecoveryKey = 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-AAAA'; // 32 characters Base32 key

    setUp(() {
      shamir = ShamirRecovery();
    });

    test('1. Correct reconstruction from exactly M shares', () {
      // Split using 3-of-5
      final result = shamir.splitRecoveryKey(recoveryKey: testRecoveryKey, m: 3, n: 5);
      expect(result.shares.length, equals(5));
      expect(result.epochId, isNotEmpty);

      // Collect exactly 3 shares (e.g. shares 0, 2, 4)
      final collectedShares = [
        result.shares[0].encodedShare,
        result.shares[2].encodedShare,
        result.shares[4].encodedShare,
      ];

      final reconstructedKey = shamir.combineShares(collectedShares);
      expect(reconstructedKey, equals(testRecoveryKey));

      // Test with all 5 shares (superset is valid)
      final allShares = result.shares.map((s) => s.encodedShare).toList();
      final reconstructedAll = shamir.combineShares(allShares);
      expect(reconstructedAll, equals(testRecoveryKey));
    });

    test('2. No partial information leakage from M-1 shares', () {
      // Split using 3-of-5
      final result = shamir.splitRecoveryKey(recoveryKey: testRecoveryKey, m: 3, n: 5);

      // Take only 2 shares (M-1)
      final collectedShares = [
        result.shares[0].encodedShare,
        result.shares[1].encodedShare,
      ];

      // Recombining fewer than M shares MUST fail and throw an ArgumentError
      expect(
        () => shamir.combineShares(collectedShares),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('3. Old-share invalidation after regeneration', () {
      // Setup first share set (epoch A)
      final result1 = shamir.splitRecoveryKey(recoveryKey: testRecoveryKey, m: 3, n: 5);
      final epochId1 = result1.epochId;

      // Setup second share set (epoch B)
      final result2 = shamir.splitRecoveryKey(recoveryKey: testRecoveryKey, m: 3, n: 5);
      final epochId2 = result2.epochId;

      expect(epochId1, isNot(equals(epochId2)));

      // If we mix shares from epoch A and epoch B, combineShares MUST throw an ArgumentError
      // because the epochId check fails.
      final mixedShares = [
        result1.shares[0].encodedShare,
        result1.shares[1].encodedShare,
        result2.shares[2].encodedShare,
      ];

      expect(
        () => shamir.combineShares(mixedShares),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
