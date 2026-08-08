import { Injectable, NotFoundException, BadRequestException, ForbiddenException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In } from 'typeorm';
import { EncryptedVaultItem } from './entities/encrypted-vault-item.entity';
import { VaultKey } from './entities/vault-key.entity';
import { UserVault } from './entities/user-vault.entity';
import { randomUUID } from 'crypto';

export interface EncryptedVaultItemDto {
  id: string;
  encryptedBlob: string;
  nonce: string;
  version: number;
  updatedAt: string;
  isDeleted: boolean;
  vaultId?: string;
  folderId?: string;
}

export interface UserVaultDto {
  id: string;
  name: string;
  salt: string;
  wrappedKey: string;
  recoverySalt?: string;
  recoveryWrappedKey?: string;
  isDefault: boolean;
  createdAt: string;
}

@Injectable()
export class SyncService {
  constructor(
    @InjectRepository(EncryptedVaultItem)
    private readonly vaultItemRepository: Repository<EncryptedVaultItem>,
    @InjectRepository(VaultKey)
    private readonly vaultKeyRepository: Repository<VaultKey>,
    @InjectRepository(UserVault)
    private readonly userVaultRepository: Repository<UserVault>,
  ) {}

  // ── Multi-Vault Management ──────────────────────────────────────────────────

  public async getUserVaults(userId: string): Promise<UserVaultDto[]> {
    const normalizedUserId = userId.toLowerCase();
    const vaults = await this.userVaultRepository.find({
      where: { userId: normalizedUserId },
      order: { createdAt: 'ASC' },
    });

    if (vaults.length === 0) {
      // Check legacy VaultKey table for backward compatibility
      const legacyKey = await this.vaultKeyRepository.findOne({
        where: { userId: normalizedUserId },
      });
      if (legacyKey) {
        const defaultVault = this.userVaultRepository.create({
          id: randomUUID(),
          userId: normalizedUserId,
          name: 'Personal Vault',
          salt: legacyKey.salt,
          wrappedKey: legacyKey.wrappedKey,
          recoverySalt: legacyKey.recoverySalt,
          recoveryWrappedKey: legacyKey.recoveryWrappedKey,
          isDefault: true,
        });
        await this.userVaultRepository.save(defaultVault);
        return [this.mapVaultToDto(defaultVault)];
      }
    }

    return vaults.map(this.mapVaultToDto);
  }

  public async createUserVault(
    userId: string,
    dto: {
      name: string;
      salt: string;
      wrappedKey: string;
      recoverySalt?: string;
      recoveryWrappedKey?: string;
      isDefault?: boolean;
    },
  ): Promise<UserVaultDto> {
    const normalizedUserId = userId.toLowerCase();
    const existingVaults = await this.userVaultRepository.find({
      where: { userId: normalizedUserId },
    });

    const isFirstVault = existingVaults.length === 0;
    const isDefault = dto.isDefault ?? isFirstVault;

    if (isDefault && !isFirstVault) {
      // Reset existing default vaults if new one is set as default
      await this.userVaultRepository.update({ userId: normalizedUserId }, { isDefault: false });
    }

    const vault = this.userVaultRepository.create({
      id: randomUUID(),
      userId: normalizedUserId,
      name: dto.name || 'Personal Vault',
      salt: dto.salt,
      wrappedKey: dto.wrappedKey,
      recoverySalt: dto.recoverySalt,
      recoveryWrappedKey: dto.recoveryWrappedKey,
      isDefault,
    });

    await this.userVaultRepository.save(vault);
    return this.mapVaultToDto(vault);
  }

  public async updateUserVault(
    userId: string,
    vaultId: string,
    dto: { name?: string; salt?: string; wrappedKey?: string },
  ): Promise<UserVaultDto> {
    const vault = await this.userVaultRepository.findOne({
      where: { id: vaultId, userId: userId.toLowerCase() },
    });

    if (!vault) {
      throw new NotFoundException(`Vault ${vaultId} not found for this user`);
    }

    if (dto.name !== undefined) vault.name = dto.name;
    if (dto.salt !== undefined) vault.salt = dto.salt;
    if (dto.wrappedKey !== undefined) vault.wrappedKey = dto.wrappedKey;

    await this.userVaultRepository.save(vault);
    return this.mapVaultToDto(vault);
  }

  public async deleteUserVault(userId: string, vaultId: string): Promise<void> {
    const normalizedUserId = userId.toLowerCase();
    const vaults = await this.userVaultRepository.find({
      where: { userId: normalizedUserId },
    });

    if (vaults.length <= 1) {
      throw new BadRequestException('Cannot delete the user\'s only remaining vault');
    }

    const vault = vaults.find((v) => v.id === vaultId);
    if (!vault) {
      throw new NotFoundException(`Vault ${vaultId} not found`);
    }

    await this.userVaultRepository.remove(vault);
    // Hard delete or mark items under this vault
    await this.vaultItemRepository.delete({ vaultId });
  }

  // ── Sync Pull / Push ───────────────────────────────────────────────────────

  public async pull(userId: string, vaultId?: string): Promise<EncryptedVaultItemDto[]> {
    const normalizedUserId = userId.toLowerCase();
    let userUuid = normalizedUserId;

    try {
      if (normalizedUserId.includes('@')) {
        const userRows = await this.vaultItemRepository.manager.query(
          `SELECT id FROM users WHERE LOWER(username) = $1 OR LOWER(email) = $1 LIMIT 1`,
          [normalizedUserId],
        );
        if (Array.isArray(userRows) && userRows.length > 0 && userRows[0].id) {
          userUuid = userRows[0].id.toLowerCase();
        }
      }
    } catch (_) {}

    const whereConditions: Array<Record<string, any>> = [];

    // Query wrapped_key_recipients table for folders shared with this user
    let sharedFolderIds: string[] = [];
    try {
      const sharedRows = await this.vaultItemRepository.manager.query(
        `SELECT DISTINCT folder_id FROM wrapped_key_recipients WHERE (LOWER(recipient_user_id) = $1 OR LOWER(recipient_user_id) = $2) AND revoked_at IS NULL`,
        [normalizedUserId, userUuid],
      );
      if (Array.isArray(sharedRows)) {
        sharedFolderIds = sharedRows.map((r: any) => r.folder_id).filter(Boolean);
      }
    } catch (_) {}

    if (vaultId) {
      whereConditions.push({ userId: normalizedUserId, vaultId });
      whereConditions.push({ userId: userUuid, vaultId });
      if (sharedFolderIds.includes(vaultId)) {
        whereConditions.push({ folderId: vaultId });
      }
    } else {
      whereConditions.push({ userId: normalizedUserId });
      whereConditions.push({ userId: userUuid });
      if (sharedFolderIds.length > 0) {
        whereConditions.push({ folderId: In(sharedFolderIds) });
      }
    }

    const items = await this.vaultItemRepository.find({
      where: whereConditions,
    });

    return items.map((item: EncryptedVaultItem) => ({
      id: item.id,
      encryptedBlob: item.encryptedBlob,
      nonce: item.nonce,
      version: item.version,
      updatedAt: item.updatedAt.toISOString(),
      isDeleted: item.isDeleted,
      vaultId: item.vaultId,
      folderId: item.folderId,
    }));
  }

  public async push(
    userId: string,
    items: EncryptedVaultItemDto[],
    targetVaultId?: string,
  ): Promise<EncryptedVaultItemDto[] | null> {
    const normalizedUserId = userId.toLowerCase();
    const conflicts: EncryptedVaultItemDto[] = [];

    // Detect conflicts
    for (const item of items) {
      const existing = await this.vaultItemRepository.findOne({
        where: { id: item.id },
      });
      if (existing) {
        if (item.version < existing.version) {
          conflicts.push(this.mapItemToDto(existing));
        } else if (item.version === existing.version) {
          if (
            item.encryptedBlob !== existing.encryptedBlob ||
            item.nonce !== existing.nonce ||
            item.isDeleted !== existing.isDeleted
          ) {
            conflicts.push(this.mapItemToDto(existing));
          }
        }
      }
    }

    if (conflicts.length > 0) {
      return conflicts;
    }

    // Save items
    for (const item of items) {
      const existing = await this.vaultItemRepository.findOne({
        where: { id: item.id },
      });
      const resolvedVaultId = item.vaultId || targetVaultId;

      if (existing) {
        existing.encryptedBlob = item.encryptedBlob;
        existing.nonce = item.nonce;
        existing.version = item.version;
        existing.updatedAt = new Date(item.updatedAt);
        existing.isDeleted = item.isDeleted;
        if (resolvedVaultId) existing.vaultId = resolvedVaultId;
        if (item.folderId) existing.folderId = item.folderId;
        await this.vaultItemRepository.save(existing);
      } else {
        const newItem = this.vaultItemRepository.create({
          id: item.id,
          userId: normalizedUserId,
          vaultId: resolvedVaultId,
          encryptedBlob: item.encryptedBlob,
          nonce: item.nonce,
          version: item.version,
          updatedAt: new Date(item.updatedAt),
          isDeleted: item.isDeleted,
          folderId: item.folderId,
        });
        await this.vaultItemRepository.save(newItem);
      }
    }

    return null;
  }

  // ── Backward Compatibility Vault Key Endpoints ─────────────────────────────

  public async saveVaultKey(
    userId: string,
    salt: string,
    wrappedKey: string,
    recoverySalt?: string,
    recoveryWrappedKey?: string,
  ): Promise<void> {
    const normalizedUserId = userId.toLowerCase();
    let userVault = await this.userVaultRepository.findOne({
      where: { userId: normalizedUserId, isDefault: true },
    });

    if (!userVault) {
      userVault = await this.userVaultRepository.findOne({
        where: { userId: normalizedUserId },
      });
    }

    if (userVault) {
      userVault.salt = salt;
      userVault.wrappedKey = wrappedKey;
      userVault.recoverySalt = recoverySalt;
      userVault.recoveryWrappedKey = recoveryWrappedKey;
      await this.userVaultRepository.save(userVault);
    } else {
      await this.createUserVault(normalizedUserId, {
        name: 'Personal Vault',
        salt,
        wrappedKey,
        recoverySalt,
        recoveryWrappedKey,
        isDefault: true,
      });
    }

    // Also update legacy table for backwards test compatibility
    let legacy = await this.vaultKeyRepository.findOne({
      where: { userId: normalizedUserId },
    });
    if (legacy) {
      legacy.salt = salt;
      legacy.wrappedKey = wrappedKey;
      legacy.recoverySalt = recoverySalt;
      legacy.recoveryWrappedKey = recoveryWrappedKey;
      await this.vaultKeyRepository.save(legacy);
    } else {
      const newLegacy = this.vaultKeyRepository.create({
        userId: normalizedUserId,
        salt,
        wrappedKey,
        recoverySalt,
        recoveryWrappedKey,
      });
      await this.vaultKeyRepository.save(newLegacy);
    }
  }

  public async getVaultKey(userId: string): Promise<{
    salt: string;
    wrappedKey: string;
    recoverySalt?: string;
    recoveryWrappedKey?: string;
  } | null> {
    const normalizedUserId = userId.toLowerCase();
    const vaults = await this.getUserVaults(normalizedUserId);
    if (vaults.length > 0) {
      const defaultVault = vaults.find((v) => v.isDefault) || vaults[0];
      return {
        salt: defaultVault.salt,
        wrappedKey: defaultVault.wrappedKey,
        recoverySalt: defaultVault.recoverySalt,
        recoveryWrappedKey: defaultVault.recoveryWrappedKey,
      };
    }
    return null;
  }

  public async clear(): Promise<void> {
    await this.vaultItemRepository.clear();
    await this.vaultKeyRepository.clear();
    await this.userVaultRepository.clear();
  }

  // ── Private Helpers ───────────────────────────────────────────────────────

  private mapVaultToDto(vault: UserVault): UserVaultDto {
    return {
      id: vault.id,
      name: vault.name,
      salt: vault.salt,
      wrappedKey: vault.wrappedKey,
      recoverySalt: vault.recoverySalt ?? undefined,
      recoveryWrappedKey: vault.recoveryWrappedKey ?? undefined,
      isDefault: vault.isDefault,
      createdAt: vault.createdAt ? vault.createdAt.toISOString() : new Date().toISOString(),
    };
  }

  private mapItemToDto(item: EncryptedVaultItem): EncryptedVaultItemDto {
    return {
      id: item.id,
      encryptedBlob: item.encryptedBlob,
      nonce: item.nonce,
      version: item.version,
      updatedAt: item.updatedAt.toISOString(),
      isDeleted: item.isDeleted,
      vaultId: item.vaultId,
      folderId: item.folderId,
    };
  }
}
