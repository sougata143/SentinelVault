import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('Widget Security Model & Opt-In Gating Tests', () {
    late VaultCrypto crypto;
    late List<int> vaultKey;

    setUp(() {
      crypto = VaultCrypto();
      vaultKey = crypto.generateRandomBytes(32);
    });

    test('1. Default VaultItem isAvailableInWidget is false', () {
      final item = VaultItem(
        id: 'test-item-1',
        type: VaultItemType.totp,
        title: 'GitHub 2FA',
        tags: const [],
        favorite: false,
        vaultId: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: TotpFields(
          issuer: 'GitHub',
          accountName: 'user@example.com',
          secret: const ConcealedValue.plain('JBSWY3DPEHPK3PXP'),
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );

      expect(item.isAvailableInWidget, isFalse);
      expect(item.hasTotpSecret, isTrue);
      expect(item.totpSecret, equals('JBSWY3DPEHPK3PXP'));
    });

    test('2. VaultItem encryption & decryption preserves isAvailableInWidget = true', () async {
      final item = VaultItem(
        id: 'test-item-opt-in',
        type: VaultItemType.totp,
        title: 'AWS Root 2FA',
        tags: const ['cloud'],
        favorite: true,
        isAvailableInWidget: true,
        vaultId: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: TotpFields(
          issuer: 'AWS',
          accountName: 'admin@company.com',
          secret: const ConcealedValue.plain('HXDMVJECJJWSRB3D'),
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );

      expect(item.isAvailableInWidget, isTrue);

      final enc = await item.encrypt(vaultKey, crypto);
      final dec = await VaultItem.decrypt(enc, vaultKey, crypto);

      expect(dec.isAvailableInWidget, isTrue);
      expect(dec.title, equals('AWS Root 2FA'));
      expect(dec.totpSecret, equals('HXDMVJECJJWSRB3D'));
    });

    test('3. Opt-in Gating Filter: excludes items where isAvailableInWidget is false', () {
      final itemDisabled = VaultItem(
        id: 'disabled-1',
        type: VaultItemType.totp,
        title: 'Private Bank TOTP',
        tags: const [],
        favorite: false,
        isAvailableInWidget: false,
        vaultId: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: TotpFields(
          issuer: 'Bank',
          accountName: 'user',
          secret: const ConcealedValue.plain('JBSWY3DPEHPK3PXP'),
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );

      final itemEnabled = VaultItem(
        id: 'enabled-1',
        type: VaultItemType.totp,
        title: 'GitHub 2FA',
        tags: const [],
        favorite: false,
        isAvailableInWidget: true,
        vaultId: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: TotpFields(
          issuer: 'GitHub',
          accountName: 'user',
          secret: const ConcealedValue.plain('JBSWY3DPEHPK3PXP'),
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );

      final allItems = [itemDisabled, itemEnabled];
      final widgetEligible = allItems.where((i) => i.isAvailableInWidget && i.hasTotpSecret).toList();

      expect(widgetEligible.length, equals(1));
      expect(widgetEligible.first.id, equals('enabled-1'));
    });

    test('4. NativeCryptoBridge generateTotpCode returns RFC 6238 codes', () async {
      final bridge = getNativeCryptoBridge();
      final code = await bridge.generateTotpCode(
        secret: 'JBSWY3DPEHPK3PXP',
        timestampSec: 59,
        period: 30,
        digits: 6,
        algorithm: 'SHA1',
      );

      expect(code, isNotNull);
      expect(code.length, equals(6));
    });
  });
}
