import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/platform/android_autofill_bridge.dart';
import 'package:app/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.app/autofill');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      calls.add(methodCall);
      switch (methodCall.method) {
        case 'isAutofillServiceEnabled':
          return true;
        case 'requestSetAutofillService':
          return true;
        case 'syncVaultCredentialsForAutofill':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AndroidAutofillBridge Unit Tests', () {
    test('isAutofillServiceEnabled invokes platform channel', () async {
      final enabled = await AndroidAutofillBridge.isAutofillServiceEnabled();
      expect(enabled, isTrue);
      expect(calls.single.method, equals('isAutofillServiceEnabled'));
    });

    test('requestSetAutofillService invokes platform channel', () async {
      final result = await AndroidAutofillBridge.requestSetAutofillService();
      expect(result, isTrue);
      expect(calls.single.method, equals('requestSetAutofillService'));
    });

    test('syncVaultCredentialsForAutofill converts items and invokes platform channel', () async {
      final item = VaultItem(
        id: 'item_1',
        type: VaultItemType.login,
        title: 'GitHub',
        tags: const [],
        favorite: false,
        vaultId: 'vault_1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fields: LoginFields(
          username: 'octocat',
          password: const ConcealedValue.plain('secret_password'),
          urls: ['https://github.com/login'],
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );

      final result = await AndroidAutofillBridge.syncVaultCredentialsForAutofill([item]);
      expect(result, isTrue);
      expect(calls.single.method, equals('syncVaultCredentialsForAutofill'));
      final args = calls.single.arguments as Map;
      expect(args['credentialsJson'], contains('github.com'));
      expect(args['credentialsJson'], contains('octocat'));
    });
  });

  testWidgets('SettingsScreen renders System-Wide Android Autofill card', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          currentEmail: 'auditor@sentinelvault.io',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('System-Wide Android Autofill'), findsOneWidget);

    final tile = find.byKey(const Key('android-autofill-settings-tile'));
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(calls.any((c) => c.method == 'requestSetAutofillService'), isTrue);
  });
}
