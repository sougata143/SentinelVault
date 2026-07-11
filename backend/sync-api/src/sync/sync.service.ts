import { Injectable } from '@nestjs/common';

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
  // Map of userId -> Map of itemId -> EncryptedVaultItemDto
  private readonly store: Map<string, Map<string, EncryptedVaultItemDto>> = new Map();
  // Map of userId -> { salt: string, wrappedKey: string, recoverySalt?: string, recoveryWrappedKey?: string }
  private readonly vaultKeys: Map<
    string,
    { salt: string; wrappedKey: string; recoverySalt?: string; recoveryWrappedKey?: string }
  > = new Map();


  /**
   * Retrieves all encrypted vault items for a specific user.
   */
  public async pull(userId: string): Promise<EncryptedVaultItemDto[]> {
    const userMap = this.store.get(userId.toLowerCase());
    if (!userMap) {
      return [];
    }
    return Array.from(userMap.values());
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
    let userMap = this.store.get(normalizedUserId);
    if (!userMap) {
      userMap = new Map();
      this.store.set(normalizedUserId, userMap);
    }

    const conflicts: EncryptedVaultItemDto[] = [];

    // 1. Detect conflicts first (transactional check)
    for (const item of items) {
      const existing = userMap.get(item.id);
      if (existing) {
        if (item.version < existing.version) {
          conflicts.push(existing);
        } else if (item.version === existing.version) {
          // If versions are equal, conflict if contents/metadata differ
          if (
            item.encryptedBlob !== existing.encryptedBlob ||
            item.nonce !== existing.nonce ||
            item.isDeleted !== existing.isDeleted
          ) {
            conflicts.push(existing);
          }
        }
      }
    }

    if (conflicts.length > 0) {
      return conflicts;
    }

    // 2. Save items if no conflicts detected
    for (const item of items) {
      userMap.set(item.id, { ...item });
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
    this.vaultKeys.set(userId.toLowerCase(), {
      salt,
      wrappedKey,
      recoverySalt,
      recoveryWrappedKey,
    });
  }

  public async getVaultKey(userId: string): Promise<{
    salt: string;
    wrappedKey: string;
    recoverySalt?: string;
    recoveryWrappedKey?: string;
  } | null> {
    const data = this.vaultKeys.get(userId.toLowerCase());
    return data ? { ...data } : null;
  }

  /**
   * Clears the database. Mainly used for tests.
   */
  public async clear(): Promise<void> {
    this.store.clear();
    this.vaultKeys.clear();
  }

}
