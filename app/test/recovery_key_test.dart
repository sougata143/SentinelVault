import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/app_shell.dart';

// ---------------------------------------------------------------------------
// Pre-computed test fixtures (derived via test/scratch_derive_recovery_keys.dart
// with Argon2id memory=1024, iterations=1).
//
//   masterPassword = 'myMasterPassword123!'
//   recoveryKey    = 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH'
//   (both salt and recoverySalt are fixed byte patterns below)
// ---------------------------------------------------------------------------

List<int> _fromHex(String hex) {
  final len = hex.length ~/ 2;
  return List.generate(
      len, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
}

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

// Fixed test data
const _saltHex       = '11111111111111111111111111111111';
const _vaultKeyHex   = '2222222222222222222222222222222222222222222222222222222222222222';
const _masterKeyHex  = 'b384d2142a28a5fbf8edfef737bfecf5533927a9a687f645604ea0b5dadaa1e3';
const _wrappedKeyHex = 'b0285ec4c3348445b179dec8b5a0c6bbcec550a96f07d5ac5db9572ed81e6356105c6fae2222775af1798aa445d934c8a164d954c78e5b4758134dd9';

const _recoverySaltHex       = '33333333333333333333333333333333';
const _recoveryKey           = 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH';
const _recoveryWrappedKeyHex = '22fddf2c65cde322aef3ea8ae6c24bd1229d4bdc0963cc6b168ecd2ae81b0f3b2793d88eccd3f7b7674e206b7f5cd09eececb64df3a923130c614fe9';

// The KDF key derived from _recoveryKey + _recoverySalt.
// Derived using crypto.deriveRecoveryKdfKey which internally calls deriveMasterKey
// with cleaned recovery key ('AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH') + salt.
// We derive it lazily in the test via runAsync (one call only).
// See test/scratch_derive_recovery_keys.dart for derivation context.

const _email           = 'user@example.com';
const _correctPassword = 'myMasterPassword123!';

// ---------------------------------------------------------------------------
// FakeVaultCrypto helpers
// ---------------------------------------------------------------------------

/// Returns pre-computed keys for known (password, salt) combos instantly;
/// delegates to real implementation for any unknown input.
class _MappedFakeVaultCrypto extends VaultCrypto {
  final Map<String, List<int>> _masterKeyMap;
  final Map<String, List<int>> _recoveryKdfKeyMap;

  _MappedFakeVaultCrypto({
    required this._masterKeyMap,
    required this._recoveryKdfKeyMap,
  });

  @override
  Future<List<int>> deriveMasterKey({
    required String masterPassword,
    required List<int> salt,
  }) async {
    final key = '${masterPassword}_${_toHex(salt)}';
    return _masterKeyMap[key] ?? List<int>.filled(32, 0x99);
  }

  @override
  Future<List<int>> deriveRecoveryKdfKey({
    required String recoveryKey,
    required List<int> salt,
  }) async {
    final cleaned = recoveryKey.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
    final keyWithHyphens = '${recoveryKey}_${_toHex(salt)}';
    final keyCleaned = '${cleaned}_${_toHex(salt)}';
    return _recoveryKdfKeyMap[keyWithHyphens] ??
        _recoveryKdfKeyMap[keyCleaned] ??
        List<int>.filled(32, 0x99);
  }

  @override
  Future<List<int>> unwrapVaultKey({
    required List<int> wrappedVaultKey,
    required List<int> masterKey,
  }) async {
    if (masterKey.every((b) => b == 0x99 || b == 0xFF)) {
      throw Exception('Invalid Recovery Key or decryption failed');
    }
    return _fromHex(_vaultKeyHex);
  }
}

/// A VaultCrypto that returns a deterministic dummy key for ALL KDF calls —
/// used in settings test 2 where any key is fine (we only check upload shape).
class _AlwaysFakeVaultCrypto extends VaultCrypto {
  static final _dummyKey = List<int>.filled(32, 0x42);

  @override
  Future<List<int>> deriveMasterKey({
    required String masterPassword,
    required List<int> salt,
  }) async =>
      _dummyKey;

  @override
  Future<List<int>> deriveRecoveryKdfKey({
    required String recoveryKey,
    required List<int> salt,
  }) async =>
      _dummyKey;

  @override
  Future<List<int>> unwrapVaultKey({
    required List<int> wrappedVaultKey,
    required List<int> masterKey,
  }) async =>
      _dummyKey;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('Recovery Key Integration Tests', () {
    final vaultKeyBytes  = _fromHex(_vaultKeyHex);
    final masterKeyBytes = _fromHex(_masterKeyHex);

    setUp(() {
      VaultLockManager.instance.logout();
    });

    testWidgets(
      '1. Forgot Master Password button appears and correct Recovery Key unlocks vault',
      (WidgetTester tester) async {
        // Derive the recovery KDF key once via runAsync so we can inject it.
        late List<int> recoveryKdfKey;
        await tester.runAsync(() async {
          recoveryKdfKey = await VaultCrypto().deriveRecoveryKdfKey(
            recoveryKey: _recoveryKey,
            salt: _fromHex(_recoverySaltHex),
          );
        });

        // Build fake: override master-password KDF + recovery key KDF.
        // For the invalid recovery key 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567',
        // we return 0xFF×32 which will fail AES-GCM authentication.
        final fakeCrypto = _MappedFakeVaultCrypto(
          masterKeyMap: {
            '${_correctPassword}_$_saltHex': masterKeyBytes,
          },
          recoveryKdfKeyMap: {
            '${_recoveryKey}_$_recoverySaltHex': recoveryKdfKey,
            '${_recoveryKey.replaceAll('-', '')}_$_recoverySaltHex': recoveryKdfKey,
            'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567_$_recoverySaltHex':
                List<int>.filled(32, 0xFF),
          },
        );

        final mockClient = MockClient((request) async {
          if (request.url.path == '/sync/vault-key') {
            return http.Response(
              json.encode({
                'salt': _saltHex,
                'wrappedKey': _wrappedKeyHex,
                'recoverySalt': _recoverySaltHex,
                'recoveryWrappedKey': _recoveryWrappedKeyHex,
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: UnlockScreen(
              email: _email,
              syncBaseUrl: 'http://fake-sync',
              httpClient: mockClient,
              cryptoOverride: fakeCrypto,
            ),
          ),
        );

        // Let _fetchKeys() complete
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Recovery button should be visible (recoverySalt + recoveryWrappedKey present)
        final recoveryBtnFinder = find.byKey(const Key('use-recovery-key-button'));
        expect(recoveryBtnFinder, findsOneWidget);

        // Open recovery dialog
        await tester.tap(recoveryBtnFinder);
        await tester.pump();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(const Key('recovery-key-input-field')), findsOneWidget);

        // ── Step 1: invalid key → error ──
        await tester.enterText(
          find.byKey(const Key('recovery-key-input-field')),
          'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567',
        );
        await tester.tap(find.byKey(const Key('submit-recovery-key-button')));
        await tester.pumpAndSettle();

        expect(find.text('Invalid Recovery Key or decryption failed'), findsOneWidget);

        // ── Step 2: correct recovery key → success ──
        await tester.enterText(
          find.byKey(const Key('recovery-key-input-field')),
          _recoveryKey,
        );
        await tester.tap(find.byKey(const Key('submit-recovery-key-button')));
        // First pump: fires tap → doSubmit runs all microtasks (fake-instant crypto),
        // sets dialogLoading=false, pops dialog, calls pushAndRemoveUntil — all
        // before any frame is painted.
        await tester.pump();
        // Second pump: renders the resulting frame (AppShell route, dialog gone).
        await tester.pump(const Duration(milliseconds: 500));

        // Dialog closed, vault unlocked, AppShell shown
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(AppShell), findsOneWidget);
        expect(VaultLockManager.instance.isLocked, isFalse);
        expect(VaultLockManager.instance.masterKey, isNull);
      },
    );

    testWidgets(
      '2. Settings setup & regenerate Emergency Kit uploads correct fields and never leaks raw recovery key',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Unlock the vault
        VaultLockManager.instance.unlock(masterKeyBytes, vaultKeyBytes);

        final List<String> requests = [];

        final mockClient = MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
            return http.Response(
              json.encode({'salt': _saltHex, 'wrappedKey': _wrappedKeyHex}),
              200,
            );
          }
          if (request.method == 'POST' && request.url.path == '/sync/vault-key') {
            requests.add(request.body);
            return http.Response(json.encode({'success': true}), 200);
          }
          return http.Response('Not found', 404);
        });

        // _AlwaysFakeVaultCrypto bypasses Argon2id for any recovery key KDF call
        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              currentEmail: _email,
              syncBaseUrl: 'http://fake-sync',
              httpClient: mockClient,
              cryptoOverride: _AlwaysFakeVaultCrypto(),
            ),
          ),
        );

        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Setup Emergency Kit tile
        final tileFinder = find.byKey(const Key('settings-setup-emergency-kit-tile'));
        await tester.dragUntilVisible(
          tileFinder,
          find.byType(ListView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(tileFinder, findsOneWidget);

        await tester.tap(tileFinder);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(const Key('generated-recovery-key-text')), findsOneWidget);

        final textWidget =
            tester.widget<Text>(find.byKey(const Key('generated-recovery-key-text')));
        final generatedRK = textWidget.data!;
        expect(generatedRK, isNotEmpty);

        // Button should be disabled until checkbox is checked
        final uploadBtn = find.byKey(const Key('upload-recovery-key-button'));
        expect(tester.widget<ElevatedButton>(uploadBtn).enabled, isFalse);

        // Check the confirmation checkbox
        await tester.tap(find.byKey(const Key('confirm-saved-checkbox')));
        await tester.pump();
        expect(tester.widget<ElevatedButton>(uploadBtn).enabled, isTrue);

        // Tap upload — FakeVaultCrypto returns instantly
        await tester.tap(uploadBtn);
        await tester.pumpAndSettle();

        // Dialog must be dismissed
        expect(find.byType(AlertDialog), findsNothing);
        // Exactly one POST request
        expect(requests.length, equals(1));

        final Map<String, dynamic> body = json.decode(requests[0]);
        expect(body['salt'], equals(_saltHex));
        expect(body['wrappedKey'], equals(_wrappedKeyHex));
        expect(body['recoverySalt'], isNotEmpty);
        expect(body['recoveryWrappedKey'], isNotEmpty);

        // Security: raw recovery key must NOT appear in the upload payload
        expect(requests[0].contains(generatedRK), isFalse);
        expect(requests[0].contains(generatedRK.replaceAll('-', '')), isFalse);
      },
    );

    test(
      '3. Recovery Key invalidation logic (old key rejected after regeneration)',
      () async {
        final crypto = VaultCrypto();

        final rk1 = crypto.generateRecoveryKey();
        final salt1 = crypto.generateRandomBytes(16);
        final rkk1 = await crypto.deriveRecoveryKdfKey(recoveryKey: rk1, salt: salt1);
        await crypto.wrapVaultKey(vaultKey: vaultKeyBytes, masterKey: rkk1);

        final rk2 = crypto.generateRecoveryKey();
        final salt2 = crypto.generateRandomBytes(16);
        final rkk2 = await crypto.deriveRecoveryKdfKey(recoveryKey: rk2, salt: salt2);
        final wrappedVK2 =
            await crypto.wrapVaultKey(vaultKey: vaultKeyBytes, masterKey: rkk2);

        // Old rkk1 must fail against wrappedVK2 (different key)
        expect(
          () => crypto.unwrapVaultKey(wrappedVaultKey: wrappedVK2, masterKey: rkk1),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      },
    );
  });
}
