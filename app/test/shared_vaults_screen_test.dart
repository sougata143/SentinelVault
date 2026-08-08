import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app/features/vault/sharing/shared_vaults_screen.dart';

void main() {
  late http.Client mockHttpClient;

  setUp(() {
    mockHttpClient = MockClient((request) async {
      if (request.url.path.contains('/shared-vaults')) {
        return http.Response(
          jsonEncode({
            'vaults': [
              {
                'vaultId': 'vault_demo_1',
                'name': 'Family Shared Vault',
                'ownerUserId': 'auditor@sentinelvault.io',
                'keyVersion': 1,
                'members': [
                  {'userId': 'auditor@sentinelvault.io', 'role': 'admin', 'status': 'accepted', 'keyVersion': 1},
                  {'userId': 'spouse@family.org', 'role': 'admin', 'status': 'accepted', 'keyVersion': 1},
                  {'userId': 'kid@family.org', 'role': 'viewer', 'status': 'accepted', 'keyVersion': 1},
                ],
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
              {
                'vaultId': 'vault_demo_2',
                'name': 'DevOps & Cloud Credentials',
                'ownerUserId': 'techlead@company.com',
                'keyVersion': 2,
                'members': [
                  {'userId': 'techlead@company.com', 'role': 'admin', 'status': 'accepted', 'keyVersion': 2},
                  {'userId': 'auditor@sentinelvault.io', 'role': 'member', 'status': 'accepted', 'keyVersion': 2},
                ],
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
            ]
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });
  });

  testWidgets('SharedVaultsScreen renders team vaults and shows create dialog', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SharedVaultsScreen(
          currentEmail: 'auditor@sentinelvault.io',
          httpClient: mockHttpClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team & Family Shared Vaults'), findsOneWidget);
    expect(find.text('Family Shared Vault'), findsOneWidget);
    expect(find.text('DevOps & Cloud Credentials'), findsOneWidget);

    final addBtn = find.byKey(const Key('create-shared-vault-btn'));
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    expect(find.text('Create Shared Vault (Team/Family)'), findsOneWidget);
    expect(find.byKey(const Key('create-vault-name-input')), findsOneWidget);
  });

  testWidgets('SharedVaultsScreen member management dialog displays key rotation warning on member revoke', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SharedVaultsScreen(
          currentEmail: 'auditor@sentinelvault.io',
          httpClient: mockHttpClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Family Shared Vault tile
    await tester.tap(find.text('Family Shared Vault'));
    await tester.pumpAndSettle();

    // Find person_remove icon button for spouse@family.org
    final removeIcon = find.byIcon(Icons.person_remove_outlined).first;
    expect(removeIcon, findsOneWidget);

    await tester.tap(removeIcon);
    await tester.pumpAndSettle();

    expect(find.text('Revoke Member & Rotate Vault Key'), findsOneWidget);
    expect(find.textContaining('Shared Vault Key will automatically rotate'), findsOneWidget);
  });
}
