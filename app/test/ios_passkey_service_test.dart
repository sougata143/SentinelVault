import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/passkey/ios_passkey_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IosPasskeyService Unit Tests', () {
    const channelName = 'com.example.app/passkeys_ios';
    final List<MethodCall> methodCalls = [];

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (MethodCall call) async {
        methodCalls.add(call);
        if (call.method == 'isPasskeyExtensionSupported') {
          return true;
        }
        if (call.method == 'syncPasskeyToAppGroup') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), null);
    });

    test('1. Checks isPasskeyExtensionSupported returns true on iOS 17+', () async {
      final service = IosPasskeyService();
      final supported = await service.isPasskeyExtensionSupported();

      expect(supported, isTrue);
      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('isPasskeyExtensionSupported'));
    });

    test('2. Syncs encrypted passkey payload to iOS App Group', () async {
      final service = IosPasskeyService();
      const payload = '{"rpId":"github.com","credentialId":"mock_cred_123"}';
      
      final success = await service.syncPasskeyToAppGroup(payload);

      expect(success, isTrue);
      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('syncPasskeyToAppGroup'));
      expect(methodCalls.first.arguments['payload'], equals(payload));
    });
  });
}
