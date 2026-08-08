import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/widget/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetService Lock-State & Data Leak Prevention Tests', () {
    final optInItem = VaultItem(
      id: 'opt-in-1',
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
        accountName: 'dev@company.com',
        secret: const ConcealedValue.plain('JBSWY3DPEHPK3PXP'),
      ),
      customFields: const [],
      notes: const ConcealedValue.plain(''),
    );

    final optOutItem = VaultItem(
      id: 'opt-out-1',
      type: VaultItemType.totp,
      title: 'Bank 2FA',
      tags: const [],
      favorite: false,
      isAvailableInWidget: false,
      vaultId: '',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      fields: TotpFields(
        issuer: 'Bank',
        accountName: 'user@bank.com',
        secret: const ConcealedValue.plain('HXDMVJECJJWSRB3D'),
      ),
      customFields: const [],
      notes: const ConcealedValue.plain(''),
    );

    test('1. Unlocked state populates widget data ONLY for opt-in items', () async {
      final payload = await WidgetService.instance.updateWidgetData(
        items: [optInItem, optOutItem],
        isLocked: false,
      );

      expect(payload['lockState'], equals('unlocked'));
      final items = payload['items'] as List;
      expect(items.length, equals(1));
      expect(items.first['title'], equals('GitHub 2FA'));
      expect(items.first['code'], isNotNull);
      expect(items.first['code'].toString().length, equals(6));
    });

    test('2. Locked state IMMEDIATELY purges shared widget storage and sets lockState: locked', () async {
      final payload = await WidgetService.instance.updateWidgetData(
        items: [optInItem],
        isLocked: true,
      );

      expect(payload['lockState'], equals('locked'));
      final items = payload['items'] as List;
      expect(items, isEmpty);
    });

    test('3. Direct call to purgeWidgetData wipes all entries', () async {
      final payload = await WidgetService.instance.purgeWidgetData();

      expect(payload['lockState'], equals('locked'));
      final items = payload['items'] as List;
      expect(items, isEmpty);
    });

    test('4. VaultLockManager.lock() triggers widget purging callback', () async {
      bool purged = false;
      VaultLockManager.instance.onLockStateChanged = (isLocked) {
        if (isLocked) {
          WidgetService.instance.purgeWidgetData();
          purged = true;
        }
      };

      // Unlock first
      VaultLockManager.instance.unlock(List.filled(32, 1), List.filled(32, 1));
      expect(VaultLockManager.instance.isLocked, isFalse);

      // Lock vault
      VaultLockManager.instance.lock();
      expect(VaultLockManager.instance.isLocked, isTrue);
      expect(purged, isTrue);
    });

    test('5. VaultLockManager.logout() triggers widget purging callback', () async {
      bool purged = false;
      VaultLockManager.instance.onLockStateChanged = (isLocked) {
        if (isLocked) {
          WidgetService.instance.purgeWidgetData();
          purged = true;
        }
      };

      VaultLockManager.instance.unlock(List.filled(32, 1), List.filled(32, 1));
      VaultLockManager.instance.logout();
      expect(VaultLockManager.instance.isLocked, isTrue);
      expect(purged, isTrue);
    });
  });
}
