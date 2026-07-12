// Tests for FlutterPlatformSecureStorage, specifically the error-propagation
// behaviour introduced to stop the blanket catch-and-ignore pattern in
// deleteBiometricWrappedVaultKey().
//
// We cannot easily test the kIsWeb early-return branch here because kIsWeb is
// a compile-time constant (false in the VM); that path is exercised naturally
// when the test suite is run with `flutter test --platform chrome`.  What we
// *can* test in the VM is the native error propagation path.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/flutter_secure_storage_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('com.example.app/secure_storage');

  group('FlutterPlatformSecureStorage.deleteBiometricWrappedVaultKey', () {
    late FlutterPlatformSecureStorage storage;

    setUp(() {
      storage = FlutterPlatformSecureStorage();
      SecurityActivityLog.instance.clear();
    });

    // -------------------------------------------------------------------------
    // Test 1: Simulated native MethodChannel failure rethrows
    // -------------------------------------------------------------------------
    testWidgets(
      '1. Rethrows when the native MethodChannel throws (native platforms)',
      (WidgetTester tester) async {
        // Arrange: mock the channel to simulate a keystore/Secure Enclave failure.
        // ignore: deprecated_member_use
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureStorageChannel,
          (MethodCall call) async {
            if (call.method == 'deleteBiometricWrappedVaultKey') {
              throw PlatformException(
                code: 'KEYSTORE_ERROR',
                message: 'Simulated native keystore failure',
              );
            }
            return null;
          },
        );

        // Act + Assert: the exception must propagate to the caller.
        expect(
          () => storage.deleteBiometricWrappedVaultKey(),
          throwsA(isA<PlatformException>()),
          reason: 'A native channel failure must NOT be silently swallowed '
              'so that a failed biometric-cache wipe during a real duress '
              'trigger is always surfaced to the caller.',
        );

        // Clean up mock.
        // ignore: deprecated_member_use
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureStorageChannel,
          null,
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 2: SecurityActivityLog records the failure before rethrowing
    // -------------------------------------------------------------------------
    testWidgets(
      '2. Logs biometric_wipe_failure to SecurityActivityLog on native error',
      (WidgetTester tester) async {
        // Arrange
        // ignore: deprecated_member_use
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureStorageChannel,
          (MethodCall call) async {
            if (call.method == 'deleteBiometricWrappedVaultKey') {
              throw PlatformException(
                code: 'KEYSTORE_ERROR',
                message: 'Simulated native keystore failure',
              );
            }
            return null;
          },
        );

        // Act: call and swallow the expected rethrow for this specific test.
        try {
          await storage.deleteBiometricWrappedVaultKey();
        } on PlatformException {
          // Expected; we care about the log, not the exception here.
        }

        // Assert: a failure entry must have been written to the security log.
        final log = SecurityActivityLog.instance.getLog();
        expect(
          log,
          isNotEmpty,
          reason: 'SecurityActivityLog must have at least one entry after a wipe failure.',
        );
        expect(
          log.first.type,
          equals('biometric_wipe_failure'),
          reason: 'The log entry type must be biometric_wipe_failure.',
        );
        expect(
          log.first.itemCount,
          equals(0),
          reason: 'itemCount for a wipe failure event must be 0 (no vault items involved).',
        );

        // Clean up mock.
        // ignore: deprecated_member_use
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureStorageChannel,
          null,
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 3: Successful call does NOT write a failure log entry
    // -------------------------------------------------------------------------
    testWidgets(
      '3. Successful deleteBiometricWrappedVaultKey does not pollute the log',
      (WidgetTester tester) async {
        // Arrange: channel responds successfully (returns null = success).
        // ignore: deprecated_member_use
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureStorageChannel,
          (MethodCall call) async => null,
        );

        // Act
        await storage.deleteBiometricWrappedVaultKey();

        // Assert
        final log = SecurityActivityLog.instance.getLog();
        final wipeFailureEntries =
            log.where((e) => e.type == 'biometric_wipe_failure').toList();
        expect(
          wipeFailureEntries,
          isEmpty,
          reason: 'A successful wipe must not write a failure entry to the log.',
        );

        // Clean up mock.
        // ignore: deprecated_member_use
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureStorageChannel,
          null,
        );
      },
    );
  });
}
