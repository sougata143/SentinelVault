// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Key Directory Service
//
//  In-memory store (replace with a durable DB — PostgreSQL / DynamoDB — before
//  production). This service is the ONLY component allowed to hold user public
//  keys and ciphertext-wrapped Folder Keys. It MUST NOT accept or persist any
//  private key, raw Folder Key, or plaintext vault data.
// ─────────────────────────────────────────────────────────────────────────────
import { Injectable, NotFoundException, ConflictException, BadRequestException } from '@nestjs/common';
import {
  PublishKeyBundleDto,
  PublishWrappedKeysDto,
  RevokeRecipientDto,
  FetchWrappedKeyDto,
  WrappedKeyRecordDto,
} from './key-directory.dto';

// ── In-memory models ──────────────────────────────────────────────────────────

interface KeyBundle {
  userId: string;
  x25519PublicKey: string;
  ed25519PublicKey: string;
  mlkemEncapsulationKey: string;
  mldsaVerifyingKey: string;
  keyFingerprint: string;
  publishedAt: Date;
  updatedAt: Date;
}

interface WrappedKeyVersion {
  folderId: string;
  keyVersion: string;
  publishedAt: Date;
  /** Map of recipientUserId → wrapped key record */
  recipients: Map<string, WrappedKeyRecordDto>;
}

@Injectable()
export class KeyDirectoryService {
  // userId → KeyBundle
  private readonly keyBundles = new Map<string, KeyBundle>();

  // folderId → ordered list of WrappedKeyVersion (newest last)
  private readonly wrappedKeys = new Map<string, WrappedKeyVersion[]>();

  // ── Public Key Directory ────────────────────────────────────────────────────

  /**
   * Publishes or rotates a user's public key bundle.
   * Key rotation is allowed; the new bundle replaces the old one for future
   * share operations. Existing wrapped copies remain valid — recipients stored
   * the ek that was current at wrap time.
   */
  publishKeyBundle(dto: PublishKeyBundleDto): KeyBundle {
    const existing = this.keyBundles.get(dto.userId);
    const bundle: KeyBundle = {
      userId: dto.userId,
      x25519PublicKey: dto.x25519PublicKey,
      ed25519PublicKey: dto.ed25519PublicKey,
      mlkemEncapsulationKey: dto.mlkemEncapsulationKey,
      mldsaVerifyingKey: dto.mldsaVerifyingKey,
      keyFingerprint: dto.keyFingerprint,
      publishedAt: existing?.publishedAt ?? new Date(),
      updatedAt: new Date(),
    };
    this.keyBundles.set(dto.userId, bundle);
    return bundle;
  }

  /**
   * Returns the public key bundle for a user.
   * Callers MUST verify the returned keyFingerprint out-of-band (e.g. via a
   * QR code / safety-number comparison) before trusting the public keys.
   */
  getKeyBundle(userId: string): KeyBundle {
    const bundle = this.keyBundles.get(userId);
    if (!bundle) {
      throw new NotFoundException(`No key bundle found for user ${userId}`);
    }
    return bundle;
  }

  // ── Wrapped Folder Key Management ──────────────────────────────────────────

  /**
   * Publishes a new version of wrapped Folder Key records for a folder.
   * The client has already: generated a new Folder Key, wrapped it for every
   * current recipient using hybrid_encapsulate, and sends ONLY ciphertext here.
   *
   * Enforces monotonic key versioning to prevent rollback attacks.
   */
  publishWrappedKeys(ownerUserId: string, dto: PublishWrappedKeysDto): void {
    const existing = this.wrappedKeys.get(dto.folderId) ?? [];

    // Version must be strictly greater than the current latest
    if (existing.length > 0) {
      const lastVersion = existing[existing.length - 1]?.keyVersion;
      if (lastVersion !== undefined && dto.keyVersion <= lastVersion) {
        throw new ConflictException(
          `Key version ${dto.keyVersion} is not greater than current version ${lastVersion}`,
        );
      }
    }

    const recipientMap = new Map<string, WrappedKeyRecordDto>();
    for (const rec of dto.recipients) {
      recipientMap.set(rec.recipientUserId, rec);
    }

    const version: WrappedKeyVersion = {
      folderId: dto.folderId,
      keyVersion: dto.keyVersion,
      publishedAt: new Date(),
      recipients: recipientMap,
    };

    existing.push(version);
    this.wrappedKeys.set(dto.folderId, existing);
  }

  /**
   * Revokes a recipient's access by:
   *  1. Accepting a new Folder Key version wrapped for remaining recipients only.
   *  2. Removing the revoked recipient's entry from the new version.
   *
   * The revoked recipient's OLD wrapped copies remain in historical versions
   * but the new version (and all future content) is inaccessible to them.
   */
  revokeRecipient(ownerUserId: string, dto: RevokeRecipientDto): void {
    // Ensure revoked user is NOT in the remainingRecipients list
    const alreadyIncluded = dto.remainingRecipients.some(
      (r) => r.recipientUserId === dto.recipientUserId,
    );
    if (alreadyIncluded) {
      throw new BadRequestException(
        'Revoked recipient must not appear in remainingRecipients',
      );
    }

    this.publishWrappedKeys(ownerUserId, {
      folderId: dto.folderId,
      keyVersion: dto.newKeyVersion,
      recipients: dto.remainingRecipients,
    });
  }

  /**
   * Fetches the wrapped Folder Key record for the authenticated calling user.
   * Returns the requested version (or the latest if not specified).
   *
   * Security: each recipient only receives their own wrapped record —
   * the server never returns another user's wrapped copy.
   */
  fetchWrappedKey(
    callerUserId: string,
    dto: FetchWrappedKeyDto,
  ): WrappedKeyRecordDto {
    const versions = this.wrappedKeys.get(dto.folderId);
    if (!versions || versions.length === 0) {
      throw new NotFoundException(`No wrapped keys found for folder ${dto.folderId}`);
    }

    let version: WrappedKeyVersion | undefined;
    if (dto.keyVersion !== undefined) {
      version = versions.find((v) => v.keyVersion === dto.keyVersion);
      if (!version) {
        throw new NotFoundException(
          `Key version ${dto.keyVersion} not found for folder ${dto.folderId}`,
        );
      }
    } else {
      version = versions[versions.length - 1];
    }

    const record = version!.recipients.get(callerUserId);
    if (!record) {
      throw new NotFoundException(
        `No wrapped key found for caller in folder ${dto.folderId} version ${version!.keyVersion}`,
      );
    }

    return record;
  }

  /**
   * Returns the current (latest) key version string for a folder.
   * Clients use this to detect when a rotation has occurred.
   */
  getCurrentKeyVersion(folderId: string): string | null {
    const versions = this.wrappedKeys.get(folderId);
    if (!versions || versions.length === 0) return null;
    return versions[versions.length - 1]?.keyVersion ?? null;
  }
}
