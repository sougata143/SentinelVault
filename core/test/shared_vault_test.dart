import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('SharedVault & SharedVaultRole Tests', () {
    test('SharedVaultRole permissions check', () {
      expect(SharedVaultRole.admin.canManageMembers, isTrue);
      expect(SharedVaultRole.admin.canWriteItems, isTrue);
      expect(SharedVaultRole.admin.canRotateKeys, isTrue);

      expect(SharedVaultRole.member.canManageMembers, isFalse);
      expect(SharedVaultRole.member.canWriteItems, isTrue);
      expect(SharedVaultRole.member.canRotateKeys, isFalse);

      expect(SharedVaultRole.viewer.canManageMembers, isFalse);
      expect(SharedVaultRole.viewer.canWriteItems, isFalse);
      expect(SharedVaultRole.viewer.canRotateKeys, isFalse);
    });

    test('SharedVault json serialization and deserialization', () {
      final now = DateTime.now().toUtc();
      final vault = SharedVault(
        vaultId: 'vault_123',
        name: 'Engineering Team Vault',
        ownerUserId: 'alice@company.com',
        keyVersion: 2,
        members: [
          const SharedVaultMember(
            userId: 'alice@company.com',
            role: SharedVaultRole.admin,
            status: 'accepted',
            keyVersion: 2,
            wrappedKeyPayload: 'payload_alice',
          ),
          const SharedVaultMember(
            userId: 'bob@company.com',
            role: SharedVaultRole.member,
            status: 'accepted',
            keyVersion: 2,
            wrappedKeyPayload: 'payload_bob',
          ),
          const SharedVaultMember(
            userId: 'charlie@company.com',
            role: SharedVaultRole.viewer,
            status: 'pending',
            keyVersion: 2,
          ),
        ],
        createdAt: now,
      );

      final jsonMap = vault.toJson();
      expect(jsonMap['vaultId'], equals('vault_123'));
      expect(jsonMap['keyVersion'], equals(2));
      expect((jsonMap['members'] as List).length, equals(3));

      final restored = SharedVault.fromJson(jsonMap);
      expect(restored.vaultId, equals('vault_123'));
      expect(restored.name, equals('Engineering Team Vault'));
      expect(restored.members.length, equals(3));
      expect(restored.members[0].role, equals(SharedVaultRole.admin));
      expect(restored.members[1].role, equals(SharedVaultRole.member));
      expect(restored.members[2].role, equals(SharedVaultRole.viewer));
      expect(restored.members[2].status, equals('pending'));
    });
  });
}
