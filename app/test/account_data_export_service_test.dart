import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/export/account_data_export_service.dart';
import 'package:app/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testItem = VaultItem(
    id: 'item_github',
    type: VaultItemType.login,
    title: 'GitHub Credentials',
    tags: const ['work'],
    favorite: true,
    vaultId: 'vault_1',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    fields: LoginFields(
      username: 'octocat',
      password: const ConcealedValue.plain('supersecret'),
      urls: ['https://github.com/login'],
      otpSecret: const ConcealedValue.plain(''),
      passwordHistory: const [],
    ),
    customFields: const [],
    notes: const ConcealedValue.plain('Primary work account'),
  );

  group('AccountDataExportService Tests', () {
    test('generateAccountDataExport produces exact documented scope', () async {
      final exportData = await AccountDataExportService.generateAccountDataExport(
        userEmail: 'auditor@sentinelvault.io',
        localVaultItems: [testItem],
        activeSessions: [
          {'deviceLabel': 'Chrome on Windows', 'loginMethod': 'password'}
        ],
        auditLogs: [
          SecurityActivity(
            type: 'EXPORT_ACCOUNT_DATA',
            itemCount: 1,
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(exportData['\$schema'], equals('https://sentinelvault.io/schemas/account_export_v1.json'));
      expect(exportData['exportVersion'], equals('1.0.0'));
      expect(exportData['accountProfile']['userId'], equals('auditor@sentinelvault.io'));

      final vaultItems = exportData['vaultItems'] as List;
      expect(vaultItems.length, equals(1));
      expect(vaultItems[0]['title'], equals('GitHub Credentials'));
      expect(vaultItems[0]['username'], equals('octocat'));
      expect(vaultItems[0]['password'], equals('supersecret'));

      final sessions = exportData['deviceSessions'] as List;
      expect(sessions.length, equals(1));
      expect(sessions[0]['deviceLabel'], equals('Chrome on Windows'));

      final logs = exportData['auditLogHistory'] as List;
      expect(logs.length, equals(1));
      expect(logs[0]['type'], equals('EXPORT_ACCOUNT_DATA'));
    });

    test('generateAccountDataExport enforces strict cross-user isolation in sharing', () async {
      final exportData = await AccountDataExportService.generateAccountDataExport(
        userEmail: 'auditor@sentinelvault.io',
        localVaultItems: [],
        sharedVaults: [
          {
            'vaultId': 'vault_1',
            'name': 'Auditor Shared Vault',
            'ownerUserId': 'auditor@sentinelvault.io',
            'myRole': 'admin',
          },
          {
            'vaultId': 'vault_other',
            'name': 'Unrelated Secret Vault',
            'ownerUserId': 'attacker@malicious.com',
            // No myRole and not owner
          },
        ],
      );

      final sharing = exportData['sharingRelationships'] as Map<String, dynamic>;
      final teamVaults = sharing['teamSharedVaults'] as List;

      expect(teamVaults.length, equals(1));
      expect(teamVaults[0]['name'], equals('Auditor Shared Vault'));
    });
  });

  testWidgets('SettingsScreen opens Download My Data dialog and prompts for Master Password', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          currentEmail: 'auditor@sentinelvault.io',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('download-my-data-tile'));
    await tester.dragUntilVisible(
      tile,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Download My Data (Account Export)'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('Download My Data (Account Export)'), findsNWidgets(2));
    expect(find.byKey(const Key('export-master-password-input')), findsOneWidget);
    expect(find.byKey(const Key('confirm-download-my-data-btn')), findsOneWidget);

    // Enter master password and generate
    await tester.enterText(find.byKey(const Key('export-master-password-input')), 'MyMasterPassword123!');
    await tester.tap(find.byKey(const Key('confirm-download-my-data-btn')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Account export generated successfully'), findsOneWidget);
  });
}
