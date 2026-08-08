import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/config/api_config.dart';
import 'package:app/features/settings/settings_screen.dart';

void main() {
  tearDown(() {
    ApiConfig.customServerUrl = null;
  });

  testWidgets('SettingsScreen allows entering and saving custom server URL', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          currentEmail: 'test@sentinelvault.io',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Self-Hosted Backend URL'), findsOneWidget);

    final inputFinder = find.byKey(const Key('settings-server-url-input'));
    expect(inputFinder, findsOneWidget);

    await tester.enterText(inputFinder, 'https://vault.customdomain.org');
    await tester.tap(find.byKey(const Key('save-server-url-btn')));
    await tester.pumpAndSettle();

    expect(ApiConfig.customServerUrl, equals('https://vault.customdomain.org'));
    expect(ApiConfig.authBaseUrl, equals('https://vault.customdomain.org:3001'));
  });

  testWidgets('SettingsScreen allows resetting custom server URL', (WidgetTester tester) async {
    ApiConfig.customServerUrl = 'https://vault.customdomain.org';

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          currentEmail: 'test@sentinelvault.io',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reset-server-url-btn')));
    await tester.pumpAndSettle();

    expect(ApiConfig.customServerUrl, isNull);
    expect(ApiConfig.authBaseUrl, contains('3001'));
  });
}
