import {
  Injectable, NotFoundException, BadRequestException, ForbiddenException, ConflictException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import {
  CreateSharedVaultDto, AddVaultMemberDto, SharedVaultRole, RotateVaultKeysDto,
} from './shared-vault.dto';

export interface SharedVaultMemberRecord {
  userId: string;
  role: SharedVaultRole;
  status: 'accepted' | 'pending' | 'revoked';
  keyVersion: number;
  wrappedKeyPayload: string;
  joinedAt: Date;
}

export interface SharedVaultRecord {
  vaultId: string;
  name: string;
  ownerUserId: string;
  keyVersion: number;
  members: Map<string, SharedVaultMemberRecord>;
  createdAt: Date;
}

@Injectable()
export class SharedVaultService {
  private readonly vaults = new Map<string, SharedVaultRecord>();

  // ── Create Shared Vault ───────────────────────────────────────────────────

  createVault(ownerUserId: string, dto: CreateSharedVaultDto): SharedVaultRecord {
    if (!dto.name || dto.name.trim().length === 0) {
      throw new BadRequestException('Vault name is required');
    }

    const vaultId = randomUUID();
    const membersMap = new Map<string, SharedVaultMemberRecord>();

    // Add owner as Admin
    const ownerMemberInput = dto.members?.find((m) => m.userId === ownerUserId);
    membersMap.set(ownerUserId, {
      userId: ownerUserId,
      role: 'admin',
      status: 'accepted',
      keyVersion: 1,
      wrappedKeyPayload: ownerMemberInput?.wrappedKeyPayload || 'owner_wrapped_key',
      joinedAt: new Date(),
    });

    // Add additional members
    if (dto.members) {
      for (const m of dto.members) {
        if (m.userId !== ownerUserId) {
          membersMap.set(m.userId, {
            userId: m.userId,
            role: m.role || 'viewer',
            status: 'pending',
            keyVersion: 1,
            wrappedKeyPayload: m.wrappedKeyPayload,
            joinedAt: new Date(),
          });
        }
      }
    }

    const vault: SharedVaultRecord = {
      vaultId,
      name: dto.name.trim(),
      ownerUserId,
      keyVersion: 1,
      members: membersMap,
      createdAt: new Date(),
    };

    this.vaults.set(vaultId, vault);
    return vault;
  }

  // ── List Vaults for User ──────────────────────────────────────────────────

  getVaultsForUser(userId: string): any[] {
    const userVaults: any[] = [];
    for (const vault of this.vaults.values()) {
      const member = vault.members.get(userId);
      if (member && member.status !== 'revoked') {
        userVaults.push({
          vaultId: vault.vaultId,
          name: vault.name,
          ownerUserId: vault.ownerUserId,
          keyVersion: vault.keyVersion,
          myRole: member.role,
          myWrappedKeyPayload: member.wrappedKeyPayload,
          memberCount: vault.members.size,
          createdAt: vault.createdAt,
        });
      }
    }
    return userVaults;
  }

  // ── Get Vault Details ─────────────────────────────────────────────────────

  getVaultDetails(callerUserId: string, vaultId: string): any {
    const vault = this.getVaultOrThrow(vaultId);
    const callerMember = vault.members.get(callerUserId);
    if (!callerMember || callerMember.status === 'revoked') {
      throw new ForbiddenException('Access denied to this shared vault');
    }

    const membersList = Array.from(vault.members.values()).map((m) => ({
      userId: m.userId,
      role: m.role,
      status: m.status,
      keyVersion: m.keyVersion,
      joinedAt: m.joinedAt,
    }));

    return {
      vaultId: vault.vaultId,
      name: vault.name,
      ownerUserId: vault.ownerUserId,
      keyVersion: vault.keyVersion,
      myRole: callerMember.role,
      myWrappedKeyPayload: callerMember.wrappedKeyPayload,
      members: membersList,
      createdAt: vault.createdAt,
    };
  }

  // ── Add Member ────────────────────────────────────────────────────────────

  addMember(callerUserId: string, vaultId: string, dto: AddVaultMemberDto): any {
    const vault = this.getVaultOrThrow(vaultId);
    this.assertAdminRole(vault, callerUserId);

    if (vault.members.has(dto.userId)) {
      const existing = vault.members.get(dto.userId)!;
      if (existing.status !== 'revoked') {
        throw new ConflictException('User is already a member of this shared vault');
      }
    }

    const newMember: SharedVaultMemberRecord = {
      userId: dto.userId,
      role: dto.role || 'viewer',
      status: 'pending',
      keyVersion: vault.keyVersion,
      wrappedKeyPayload: dto.wrappedKeyPayload,
      joinedAt: new Date(),
    };

    vault.members.set(dto.userId, newMember);
    return { success: true, member: newMember };
  }

  // ── Remove Member & Require Key Rotation ──────────────────────────────

  removeMember(callerUserId: string, vaultId: string, targetUserId: string): any {
    const vault = this.getVaultOrThrow(vaultId);
    this.assertAdminRole(vault, callerUserId);

    if (targetUserId === vault.ownerUserId) {
      throw new BadRequestException('Cannot remove the owner of the shared vault');
    }

    const member = vault.members.get(targetUserId);
    if (!member || member.status === 'revoked') {
      throw new NotFoundException('Member not found in this vault');
    }

    // Mark status revoked and remove key material
    member.status = 'revoked';
    member.wrappedKeyPayload = '';

    return {
      success: true,
      message: `Member ${targetUserId} removed. Shared Vault Key rotation is required.`,
      requiresKeyRotation: true,
      remainingMembers: Array.from(vault.members.values())
        .filter((m) => m.status !== 'revoked')
        .map((m) => m.userId),
    };
  }

  // ── Rotate Keys for Remaining Members ────────────────────────────────────

  rotateKeys(callerUserId: string, vaultId: string, dto: RotateVaultKeysDto): any {
    const vault = this.getVaultOrThrow(vaultId);
    this.assertAdminRole(vault, callerUserId);

    if (dto.keyVersion <= vault.keyVersion) {
      throw new BadRequestException(`New keyVersion must be greater than current version (${vault.keyVersion})`);
    }

    vault.keyVersion = dto.keyVersion;

    for (const wrap of dto.wrappedKeys) {
      const member = vault.members.get(wrap.userId);
      if (member && member.status !== 'revoked') {
        member.keyVersion = dto.keyVersion;
        member.wrappedKeyPayload = wrap.wrappedKeyPayload;
      }
    }

    return {
      success: true,
      keyVersion: vault.keyVersion,
      updatedMembersCount: dto.wrappedKeys.length,
    };
  }

  // ── Private Helpers ───────────────────────────────────────────────────────

  private getVaultOrThrow(vaultId: string): SharedVaultRecord {
    const vault = this.vaults.get(vaultId);
    if (!vault) throw new NotFoundException(`Shared vault ${vaultId} not found`);
    return vault;
  }

  private assertAdminRole(vault: SharedVaultRecord, userId: string): void {
    const member = vault.members.get(userId);
    if (!member || member.status === 'revoked' || member.role !== 'admin') {
      throw new ForbiddenException('Admin permissions required to perform this action');
    }
  }
}
