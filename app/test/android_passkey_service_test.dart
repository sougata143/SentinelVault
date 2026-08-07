import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/passkey/android_passkey_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidPasskeyService Unit Tests', () {
    const channelName = 'com.example.app/passkeys';
    final List<MethodCall> methodCalls = [];

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (MethodCall call) async {
        methodCalls.add(call);
        if (call.method == 'isPasskeyProviderSupported') {
          return true;
        }
        if (call.method == 'getPendingPasskeyIntent') {
          return {
            'action': 'com.example.app.WEBAUTHN_REGISTER',
            'rpId': 'github.com',
            'requestJson': '{"rp":{"id":"github.com","name":"GitHub"},"user":{"name":"alice@example.com","id":"dXNlcjEyMw=="},"challenge":"Y2hhbGxlbmdl"}',
            'callingPackage': 'com.android.chrome'
          };
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), null);
    });

    test('1. Checks isPasskeyProviderSupported returns true on API 34+', () async {
      final service = AndroidPasskeyService();
      final supported = await service.isPasskeyProviderSupported();

      expect(supported, isTrue);
      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('isPasskeyProviderSupported'));
    });

    test('2. Fetches pending passkey intent payload', () async {
      final service = AndroidPasskeyService();
      final pendingIntent = await service.getPendingPasskeyIntent();

      expect(pendingIntent, isNotNull);
      expect(pendingIntent!['action'], equals('com.example.app.WEBAUTHN_REGISTER'));
      expect(pendingIntent['rpId'], equals('github.com'));
      expect(pendingIntent['callingPackage'], equals('com.android.chrome'));
    });

    test('3. Parses registration request JSON correctly', () {
      final service = AndroidPasskeyService();
      const jsonStr = '{"rp":{"id":"google.com","name":"Google"},"user":{"name":"dev@google.com","id":"dXNlcjQ1Ng=="},"challenge":"YWJj"}';
      
      final parsed = service.parseRegistrationRequest(jsonStr);

      expect(parsed['rpId'], equals('google.com'));
      expect(parsed['rpName'], equals('Google'));
      expect(parsed['userName'], equals('dev@google.com'));
      expect(parsed['userHandle'], equals('dXNlcjQ1Ng=='));
    });

    test('4. Creates PasskeyVaultItem from Android CredentialManager request', () {
      final service = AndroidPasskeyService();

      final item = service.createPasskeyFromRequest(
        rpId: 'github.com',
        userName: 'alice@example.com',
        userHandle: 'dXNlcjEyMw==',
        privateKeyPem: '-----BEGIN EC PRIVATE KEY-----\nMIG...\n-----END EC PRIVATE KEY-----',
        publicKeyRaw: 'BA123...',
        cosePublicKey: 'pKV...',
      );

      expect(item.rpId, equals('github.com'));
      expect(item.userName, equals('alice@example.com'));
      expect(item.userHandle, equals('dXNlcjEyMw=='));
      expect(item.credentialId, contains('github_com'));
      expect(item.signCount, equals(0));
    });
  });
}
