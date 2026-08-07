import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/vault/item_detail.dart';

void main() {
  group('New Vault Templates UI & Detail Pane Tests', () {
    testWidgets('Renders SSH Key Pair item details with monospace font', (WidgetTester tester) async {
      final item = VaultItem(
        id: 'ssh-1',
        type: VaultItemType.sshKey,
        title: 'Production Server Key',
        tags: const ['dev', 'prod'],
        favorite: false,
        vaultId: 'v1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fields: SshKeyFields(
          keyName: 'Prod-Key-Ed25519',
          privateKey: const ConcealedValue.plain('-----BEGIN OPENSSH PRIVATE KEY-----\ntest-key\n-----END OPENSSH PRIVATE KEY-----'),
          publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...',
          passphrase: const ConcealedValue.plain('pass123'),
          keyType: 'Ed25519',
        ),
        customFields: const [],
        notes: const ConcealedValue.plain('SSH key note'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ItemDetailPane(item: item),
          ),
        ),
      );

      expect(find.text('Production Server Key'), findsAtLeastNWidgets(1));
      expect(find.text('Key Name'), findsOneWidget);
      expect(find.text('Prod-Key-Ed25519'), findsOneWidget);
      expect(find.text('Public Key (OpenSSH)'), findsOneWidget);
    });

    testWidgets('Renders Crypto Seed Phrase item and shows security reveal confirmation dialog', (WidgetTester tester) async {
      final item = VaultItem(
        id: 'seed-1',
        type: VaultItemType.cryptoSeed,
        title: 'MetaMask Primary Seed',
        tags: const ['crypto'],
        favorite: true,
        vaultId: 'v1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        fields: CryptoSeedFields(
          walletName: 'MetaMask ETH',
          seedPhrase: const ConcealedValue.plain('word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12'),
          derivationPath: "m/44'/60'/0'/0/0",
          notes: 'Primary wallet',
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ItemDetailPane(item: item),
          ),
        ),
      );

      expect(find.text('MetaMask Primary Seed'), findsAtLeastNWidgets(1));
      expect(find.text('MAX SENSITIVE'), findsOneWidget);
      expect(find.text('••••••••••••••••'), findsOneWidget);

      // Tap reveal icon button
      final revealIcon = find.byIcon(Icons.visibility_off_outlined).first;
      await tester.tap(revealIcon);
      await tester.pumpAndSettle();

      // Check security alert dialog is shown
      expect(find.text('Security Alert'), findsOneWidget);
      expect(find.textContaining('Ensure no one is looking over your shoulder'), findsOneWidget);

      // Confirm reveal
      await tester.tap(find.text('Confirm & Reveal'));
      await tester.pumpAndSettle();

      // Verify seed phrase is revealed
      expect(find.textContaining('word1 word2 word3'), findsOneWidget);
    });
  });
}
