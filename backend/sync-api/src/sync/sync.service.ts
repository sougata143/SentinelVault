import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { EncryptedVaultItem } from './entities/encrypted-vault-item.entity';
import { VaultKey } from './entities/vault-key.entity';

export interface EncryptedVaultItemDto {
  id: string;
  encryptedBlob: string;
  nonce: string;
  version: number;
  updatedAt: string;
  isDeleted: boolean;
}

@Injectable()
export class SyncService {
  constructor(
    @InjectRepository(EncryptedVaultItem)
    private readonly vaultItemRepository: Repository<EncryptedVaultItem>,
    @InjectRepository(VaultKey)
    private readonly vaultKeyRepository: Repository<VaultKey>,
  ) { }


  /**
   * Retrieves all encrypted vault items for a specific user.
   */
  public async pull(userId: string): Promise<EncryptedVaultItemDto[]> {
    const items = await this.vaultItemRepository.find({
      where: { userId: userId.toLowerCase() },
    });
    return items.map((item: EncryptedVaultItem) => ({
      id: item.id,
      encryptedBlob: item.encryptedBlob,
      nonce: item.nonce,
      version: item.version,
      updatedAt: item.updatedAt.toISOString(),
      isDeleted: item.isDeleted,
    }));
  }

  /**
   * Pushes a list of encrypted items to the server.
   * Performs validation and conflict checks on each item.
   * If any conflict is found, returns the conflicting server items.
   * Otherwise, saves the items and returns null.
   */
  public async push(
    userId: string,
    items: EncryptedVaultItemDto[],
  ): Promise<EncryptedVaultItemDto[] | null> {
    const normalizedUserId = userId.toLowerCase();
    const conflicts: EncryptedVaultItemDto[] = [];

    // 1. Detect conflicts first (transactional check)
    for (const item of items) {
      const existing = await this.vaultItemRepository.findOne({
        where: { id: item.id, userId: normalizedUserId },
      });
      if (existing) {
        if (item.version < existing.version) {
          conflicts.push({
            id: existing.id,
            encryptedBlob: existing.encryptedBlob,
            nonce: existing.nonce,
            version: existing.version,
            updatedAt: existing.updatedAt.toISOString(),
            isDeleted: existing.isDeleted,
          });
        } else if (item.version === existing.version) {
          // If versions are equal, conflict if contents/metadata differ
          if (
            item.encryptedBlob !== existing.encryptedBlob ||
            item.nonce !== existing.nonce ||
            item.isDeleted !== existing.isDeleted
          ) {
            conflicts.push({
              id: existing.id,
              encryptedBlob: existing.encryptedBlob,
              nonce: existing.nonce,
              version: existing.version,
              updatedAt: existing.updatedAt.toISOString(),
              isDeleted: existing.isDeleted,
            });
          }
        }
      }
    }

    if (conflicts.length > 0) {
      return conflicts;
    }

    // 2. Save items if no conflicts detected
    for (const item of items) {
      const existing = await this.vaultItemRepository.findOne({
        where: { id: item.id, userId: normalizedUserId },
      });
      if (existing) {
        // Update existing
        existing.encryptedBlob = item.encryptedBlob;
        existing.nonce = item.nonce;
        existing.version = item.version;
        existing.updatedAt = new Date(item.updatedAt);
        existing.isDeleted = item.isDeleted;
        await this.vaultItemRepository.save(existing);
      } else {
        // Insert new
        const newItem = this.vaultItemRepository.create({
          id: item.id,
          userId: normalizedUserId,
          encryptedBlob: item.encryptedBlob,
          nonce: item.nonce,
          version: item.version,
          updatedAt: new Date(item.updatedAt),
          isDeleted: item.isDeleted,
        });
        await this.vaultItemRepository.save(newItem);
      }
    }

    return null;
  }

  public async saveVaultKey(
    userId: string,
    salt: string,
    wrappedKey: string,
    recoverySalt?: string,
    recoveryWrappedKey?: string,
  ): Promise<void> {
    const normalizedUserId = userId.toLowerCase();
    let vaultKey = await this.vaultKeyRepository.findOne({
      where: { userId: normalizedUserId },
    });

    if (vaultKey) {
      // Update existing
      vaultKey.salt = salt;
      vaultKey.wrappedKey = wrappedKey;
      vaultKey.recoverySalt = recoverySalt;
      vaultKey.recoveryWrappedKey = recoveryWrappedKey;
      await this.vaultKeyRepository.save(vaultKey);
    } else {
      // Insert new
      const newVaultKey = this.vaultKeyRepository.create({
        userId: normalizedUserId,
        salt,
        wrappedKey,
        recoverySalt,
        recoveryWrappedKey,
      });
      await this.vaultKeyRepository.save(newVaultKey);
    }
  }

  public async getVaultKey(userId: string): Promise<{
    salt: string;
    wrappedKey: string;
    recoverySalt?: string;
    recoveryWrappedKey?: string;
  } | null> {
    const vaultKey = await this.vaultKeyRepository.findOne({
      where: { userId: userId.toLowerCase() },
    });
    if (!vaultKey) {
      return null;
    }
    return {
      salt: vaultKey.salt,
      wrappedKey: vaultKey.wrappedKey,
      recoverySalt: vaultKey.recoverySalt ?? undefined,
      recoveryWrappedKey: vaultKey.recoveryWrappedKey ?? undefined,
    };
  }

  /**
   * Clears the database. Mainly used for tests.
   */
  public async clear(): Promise<void> {
    await this.vaultItemRepository.clear();
    await this.vaultKeyRepository.clear();
  }

}
