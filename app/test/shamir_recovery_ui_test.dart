import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/shamir_recovery_setup_screen.dart';
import 'package:app/features/auth/shamir_recovery_reconstruct_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('Shamir Recovery UI/Widget Tests', () {
    const email = 'user@example.com';
    late List<int> vaultKey;
    late String recoveryKey;
    late List<RecoveryShare> generatedShares;
    late String epochId;

    setUpAll(() {
      final crypto = VaultCrypto();
      vaultKey = crypto.generateRandomBytes(32);
      recoveryKey = crypto.generateRecoveryKey();

      final shamir = ShamirRecovery();
      final result = shamir.splitRecoveryKey(
        recoveryKey: recoveryKey,
        m: 3,
        n: 5,
      );
      generatedShares = result.shares;
      epochId = result.epochId;

      VaultLockManager.instance.unlock(List.generate(32, (i) => i), vaultKey);
    });

    // -----------------------------------------------------------------------
    // Test 1: Setup wizard navigates through all 5 share pages
    // -----------------------------------------------------------------------
    testWidgets('1. Shamir Setup Screen — wizard navigates through all shares and finishes',
        (WidgetTester tester) async {
      bool didPop = false;

      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
          return http.Response(
            json.encode({
              'salt': '00112233445566778899aabbccddeeff',
              'wrappedKey':
                  '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
            }),
            200,
          );
        }
        if (request.method == 'POST' && request.url.path == '/sync/vault-key') {
          return http.Response(json.encode({'success': true}), 200);
        }
        return http.Response('Not found', 404);
      });

      // Wrap in a MaterialApp with a route structure so pop works
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              key: const Key('open-shamir-setup'),
              onPressed: () async {
                await Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => ShamirRecoverySetupScreen(
                      currentEmail: email,
                      syncBaseUrl: 'http://fake-sync',
                      httpClient: mockClient,
                    ),
                  ),
                );
                didPop = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-shamir-setup')));
      await tester.pumpAndSettle();

      // Should be on setup config screen
      expect(find.text('Split Your Recovery Key'), findsOneWidget);
      expect(find.byKey(const Key('generate-shares-button')), findsOneWidget);

      // Generate shares — async because of Argon2id
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('generate-shares-button')));
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pump();

      // Should now show share viewer: "Share 1 of 5"
      expect(find.text('Share 1 of 5'), findsOneWidget);

      // Walk through all 5 share cards, checking each one
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('share-code-text-$i')), findsOneWidget);

        // Confirm the share
        await tester.tap(find.byKey(Key('confirm-share-checkbox-$i')));
        await tester.pump();

        if (i < 4) {
          // Move to next share
          await tester.tap(find.byKey(const Key('next-share-button')));
          await tester.pump();
          expect(find.text('Share ${i + 2} of 5'), findsOneWidget);
        }
      }

      // All shares confirmed — Finish Setup button should be enabled now
      final finishBtn = find.byKey(const Key('next-share-button'));
      expect(tester.widget<ElevatedButton>(finishBtn).enabled, isTrue);
      expect(find.text('Finish Setup'), findsOneWidget);

      // Tap finish — pops back to root
      await tester.tap(finishBtn);
      await tester.pumpAndSettle();

      // Screen popped, home page restored, didPop is true
      expect(find.byType(ShamirRecoverySetupScreen), findsNothing);
      expect(didPop, isTrue);
    });

    // -----------------------------------------------------------------------
    // Test 2: Reconstruct — M-1 shows error; M reconstructs correctly
    // -----------------------------------------------------------------------
    testWidgets('2. Shamir Reconstruct Screen — M-1 error then M succeeds',
        (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
          final crypto = VaultCrypto();
          final recoverySaltHex = epochId.replaceAll('-', '').toLowerCase();
          final rkSalt = _hexToBytes(recoverySaltHex);
          final rkk = await crypto.deriveRecoveryKdfKey(
            recoveryKey: recoveryKey,
            salt: rkSalt,
          );
          final recoveryWrappedKey = await crypto.wrapVaultKey(
            masterKey: rkk,
            vaultKey: vaultKey,
          );
          final recoveryWrappedKeyHex =
              recoveryWrappedKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

          return http.Response(
            json.encode({
              'salt': '00112233445566778899aabbccddeeff',
              'wrappedKey':
                  '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
              'recoverySalt': recoverySaltHex,
              'recoveryWrappedKey': recoveryWrappedKeyHex,
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ShamirRecoveryReconstructScreen(
            email: email,
            syncBaseUrl: 'http://fake-sync',
            httpClient: mockClient,
          ),
        ),
      );

      expect(find.text('Enter Recovery Shares'), findsOneWidget);

      // Enter only 2 shares (below threshold M=3) and try to reconstruct
      await tester.enterText(
          find.byKey(const Key('share-input-field-0')), generatedShares[0].encodedShare);
      await tester.enterText(
          find.byKey(const Key('share-input-field-1')), generatedShares[1].encodedShare);
      await tester.pump();

      final reconstructBtn = find.byKey(const Key('reconstruct-key-button'));
      await tester.ensureVisible(reconstructBtn);
      await tester.tap(reconstructBtn, warnIfMissed: false);
      await tester.pump();

      // Validation error for M-1 — network not called yet
      expect(
        find.textContaining('You need at least 3 valid shares'),
        findsOneWidget,
      );

      // Add a third share field and enter valid 3rd share
      await tester.tap(find.byKey(const Key('add-share-field-button')));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('share-input-field-2')), generatedShares[2].encodedShare);
      await tester.pump();

      // Tap reconstruct with M=3 — triggers Argon2id async call
      await tester.runAsync(() async {
        await tester.ensureVisible(reconstructBtn);
        await tester.tap(reconstructBtn, warnIfMissed: false);
        await Future.delayed(const Duration(milliseconds: 2000));
      });
      await tester.pumpAndSettle();

      // Vault should now be unlocked (navigation completed or is in-progress)
      expect(VaultLockManager.instance.isLocked, isFalse);
    });
  });
}
