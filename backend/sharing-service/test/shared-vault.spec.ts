import { Test, TestingModule } from '@nestjs/testing';
import { ForbiddenException, BadRequestException } from '@nestjs/common';
import { SharedVaultService } from '../src/shared-vault/shared-vault.service';
import { SharedVaultController } from '../src/shared-vault/shared-vault.controller';

describe('SharedVaultService & SharedVaultController (Team/Family Shared Vaults)', () => {
  let service: SharedVaultService;
  let controller: SharedVaultController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [SharedVaultController],
      providers: [SharedVaultService],
    }).compile();

    service = module.get<SharedVaultService>(SharedVaultService);
    controller = module.get<SharedVaultController>(SharedVaultController);
  });

  it('should create a new team shared vault with owner as Admin', () => {
    const vault = service.createVault('alice@company.com', {
      name: 'DevOps Secrets',
      members: [
        { userId: 'bob@company.com', role: 'member', wrappedKeyPayload: 'wrapped_key_bob' },
      ],
    });

    expect(vault.vaultId).toBeDefined();
    expect(vault.name).toBe('DevOps Secrets');
    expect(vault.ownerUserId).toBe('alice@company.com');
    expect(vault.keyVersion).toBe(1);
    expect(vault.members.size).toBe(2);

    const aliceMember = vault.members.get('alice@company.com');
    expect(aliceMember?.role).toBe('admin');
    expect(aliceMember?.status).toBe('accepted');

    const bobMember = vault.members.get('bob@company.com');
    expect(bobMember?.role).toBe('member');
    expect(bobMember?.status).toBe('pending');
  });

  it('should list vaults for authorized user', () => {
    service.createVault('alice@company.com', {
      name: 'Family Vault',
      members: [{ userId: 'bob@company.com', role: 'member', wrappedKeyPayload: 'wrapped_key_bob' }],
    });

    const aliceVaults = service.getVaultsForUser('alice@company.com');
    expect(aliceVaults.length).toBe(1);
    expect(aliceVaults[0].name).toBe('Family Vault');
    expect(aliceVaults[0].myRole).toBe('admin');

    const bobVaults = service.getVaultsForUser('bob@company.com');
    expect(bobVaults.length).toBe(1);
    expect(bobVaults[0].myRole).toBe('member');

    const charlieVaults = service.getVaultsForUser('charlie@company.com');
    expect(charlieVaults.length).toBe(0);
  });

  it('should enforce Admin role requirement for member removal', () => {
    const vault = service.createVault('alice@company.com', {
      name: 'Engineering Vault',
      members: [
        { userId: 'bob@company.com', role: 'member', wrappedKeyPayload: 'key_bob' },
        { userId: 'charlie@company.com', role: 'viewer', wrappedKeyPayload: 'key_charlie' },
      ],
    });

    // Member (bob) attempts to remove Charlie -> Should fail with ForbiddenException
    expect(() => {
      service.removeMember('bob@company.com', vault.vaultId, 'charlie@company.com');
    }).toThrow(ForbiddenException);

    // Admin (alice) removes Charlie -> Should succeed and trigger key rotation required
    const result = service.removeMember('alice@company.com', vault.vaultId, 'charlie@company.com');
    expect(result.success).toBe(true);
    expect(result.requiresKeyRotation).toBe(true);
    expect(result.remainingMembers).toContain('alice@company.com');
    expect(result.remainingMembers).toContain('bob@company.com');
    expect(result.remainingMembers).not.toContain('charlie@company.com');
  });

  it('should support Admin key rotation batch update', () => {
    const vault = service.createVault('alice@company.com', {
      name: 'Finance Vault',
      members: [{ userId: 'bob@company.com', role: 'member', wrappedKeyPayload: 'key_v1_bob' }],
    });

    const rotateResult = service.rotateKeys('alice@company.com', vault.vaultId, {
      keyVersion: 2,
      wrappedKeys: [
        { userId: 'alice@company.com', wrappedKeyPayload: 'key_v2_alice' },
        { userId: 'bob@company.com', wrappedKeyPayload: 'key_v2_bob' },
      ],
    });

    expect(rotateResult.success).toBe(true);
    expect(rotateResult.keyVersion).toBe(2);

    const details = service.getVaultDetails('alice@company.com', vault.vaultId);
    expect(details.keyVersion).toBe(2);
  });

  it('should verify controller endpoints via HTTP bearer auth', () => {
    const authHeader = 'Bearer alice@company.com';
    const vault = controller.createVault(authHeader, {
      name: 'Controller Vault Test',
      members: [],
    });

    expect(vault.vaultId).toBeDefined();

    const userVaults = controller.listVaults(authHeader);
    expect(userVaults.vaults.length).toBe(1);
    expect(userVaults.vaults[0].name).toBe('Controller Vault Test');
  });
});
