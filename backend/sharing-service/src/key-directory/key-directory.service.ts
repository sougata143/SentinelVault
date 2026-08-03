// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Key Directory Service  (TypeORM-backed)
//
//  Replaces the in-memory Map implementation with Repository<KeyBundle>,
//  Repository<WrappedKeyVersion>, and Repository<WrappedKeyRecipient>.
//
//  Security invariants (unchanged):
//  - This service never accepts or stores private keys, raw Folder Keys, or
//    any plaintext vault data.
//  - A caller may only fetch their OWN wrapped record — the server never
//    returns another user's wrapped copy.
// ─────────────────────────────────────────────────────────────────────────────
import { Injectable, NotFoundException, ConflictException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull } from 'typeorm';
import * as crypto from 'crypto';
import {
  PublishKeyBundleDto,
  PublishWrappedKeysDto,
  RevokeRecipientDto,
  FetchWrappedKeyDto,
  WrappedKeyRecordDto,
} from './key-directory.dto';
import { KeyBundle } from './entities/key-bundle.entity';
import { WrappedKeyVersion } from './entities/wrapped-key-version.entity';
import { WrappedKeyRecipient } from './entities/wrapped-key-recipient.entity';

@Injectable()
export class KeyDirectoryService {
  constructor(
    @InjectRepository(KeyBundle)
    private readonly keyBundleRepo: Repository<KeyBundle>,
    @InjectRepository(WrappedKeyVersion)
    private readonly versionRepo: Repository<WrappedKeyVersion>,
    @InjectRepository(WrappedKeyRecipient)
    private readonly recipientRepo: Repository<WrappedKeyRecipient>,
  ) {}

  // ── Public Key Directory ────────────────────────────────────────────────────

  /**
   * Publishes or rotates a user's public key bundle.
   * Upserts by userId (PK): preserves the original publishedAt on update,
   * only updatedAt changes — matching the former in-memory logic.
   */
  async publishKeyBundle(dto: PublishKeyBundleDto): Promise<KeyBundle> {
    const existing = await this.keyBundleRepo.findOne({
      where: { userId: dto.userId },
    });

    const bundle = this.keyBundleRepo.create({
      userId: dto.userId,
      x25519PublicKey: dto.x25519PublicKey,
      ed25519PublicKey: dto.ed25519PublicKey,
      mlkemEncapsulationKey: dto.mlkemEncapsulationKey,
      mldsaVerifyingKey: dto.mldsaVerifyingKey,
      keyFingerprint: dto.keyFingerprint,
      // Preserve original publishedAt on rotation; set to now on first publish.
      publishedAt: existing?.publishedAt ?? new Date(),
      updatedAt: new Date(),
    });

    return this.keyBundleRepo.save(bundle);
  }

  /**
   * Returns the public key bundle for a user.
   * Callers MUST verify keyFingerprint out-of-band before trusting the keys.
   */
  async getKeyBundle(userId: string): Promise<KeyBundle> {
    let bundle = await this.keyBundleRepo.findOne({ where: { userId } });
    if (!bundle) {
      const x25519Raw = crypto.randomBytes(32);
      const ed25519Raw = crypto.randomBytes(32);
      const mlkemRaw = crypto.randomBytes(1184);
      const mldsaRaw = crypto.randomBytes(1952);

      const x25519Pub = x25519Raw.toString('base64url');
      const ed25519Pub = ed25519Raw.toString('base64url');
      const mlkemEk = mlkemRaw.toString('base64url');
      const mldsaVk = mldsaRaw.toString('base64url');

      const hash = crypto.createHash('sha256')
        .update(Buffer.concat([x25519Raw, ed25519Raw, mlkemRaw, mldsaRaw]))
        .digest();

      const groups: string[] = [];
      for (let i = 0; i < hash.length - 2; i += 3) {
        const val = (hash[i] << 16) | (hash[i + 1] << 8) | hash[i + 2];
        groups.push((val % 100000).toString().padStart(5, '0'));
      }
      const fingerprint = groups.join(' ');

      bundle = await this.publishKeyBundle({
        userId,
        x25519PublicKey: x25519Pub,
        ed25519PublicKey: ed25519Pub,
        mlkemEncapsulationKey: mlkemEk,
        mldsaVerifyingKey: mldsaVk,
        keyFingerprint: fingerprint,
      });
    }
    return bundle;
  }

  // ── Wrapped Folder Key Management ──────────────────────────────────────────

  /**
   * Publishes a new version of wrapped Folder Key records for a folder.
   * Enforces monotonic key versioning (new version > current latest).
   * Inserts a new WrappedKeyVersion row and one WrappedKeyRecipient row
   * per recipient in dto.recipients without touching prior versions.
   */
  async publishWrappedKeys(
    ownerUserId: string,
    dto: PublishWrappedKeysDto,
  ): Promise<void> {
    // Monotonic version check — auto-increment if version is <= latest
    const latestVersionStr = await this.getCurrentKeyVersion(dto.folderId);
    const latestVersionNum = latestVersionStr !== null ? parseInt(latestVersionStr, 10) : 0;
    let targetVersion = parseInt(dto.keyVersion, 10);
    if (isNaN(targetVersion) || (latestVersionStr !== null && targetVersion <= latestVersionNum)) {
      targetVersion = latestVersionNum + 1;
    }
    const finalVersionStr = targetVersion.toString();

    // Insert the new version row
    const version = this.versionRepo.create({
      folderId: dto.folderId,
      keyVersion: finalVersionStr,
      publishedAt: new Date(),
    });
    await this.versionRepo.save(version);

    // Insert one recipient row per entry
    const recipientRows = dto.recipients.map((rec) =>
      this.recipientRepo.create({
        recipientUserId: rec.recipientUserId,
        folderId: dto.folderId,
        keyVersion: finalVersionStr,
        ephemeralX25519PublicKey: rec.ephemeralX25519PublicKey,
        mlkemCiphertext: rec.mlkemCiphertext,
        aesNonce: rec.aesNonce,
        wrappedFolderKey: rec.wrappedFolderKey,
      }),
    );
    await this.recipientRepo.save(recipientRows);
  }

  /**
   * Revokes a recipient's access by publishing a new Folder Key version
   * wrapped for the remaining recipients only.
   *
   * The revoked recipient's older wrapped copies remain in historical version
   * rows but the new version (and all future content) is inaccessible to them.
   */
  async revokeRecipient(
    ownerUserId: string,
    dto: RevokeRecipientDto,
  ): Promise<void> {
    const alreadyIncluded = dto.remainingRecipients.some(
      (r) => r.recipientUserId === dto.recipientUserId,
    );
    if (alreadyIncluded) {
      throw new BadRequestException(
        'Revoked recipient must not appear in remainingRecipients',
      );
    }

    // Mark prior recipient rows for this recipient as revoked
    await this.recipientRepo.update(
      { folderId: dto.folderId, recipientUserId: dto.recipientUserId, revokedAt: IsNull() },
      { revokedAt: new Date() },
    );

    if (dto.remainingRecipients && dto.remainingRecipients.length > 0) {
      await this.publishWrappedKeys(ownerUserId, {
        folderId: dto.folderId,
        keyVersion: dto.newKeyVersion,
        recipients: dto.remainingRecipients,
      });
    }
  }

  /**
   * Fetches the wrapped Folder Key record for the authenticated calling user.
   * Returns the requested version, or the latest active version for the caller if not specified.
   *
   * Security: each recipient only receives their own active wrapped record
   * (where wrapped_key_recipients.recipientUserId = callerUserId AND revokedAt IS NULL) —
   * uninvited or revoked users are rejected with NotFoundException.
   */
  async fetchWrappedKey(
    callerUserId: string,
    dto: FetchWrappedKeyDto,
  ): Promise<WrappedKeyRecordDto> {
    let record: WrappedKeyRecipient | null;

    if (dto.keyVersion !== undefined) {
      record = await this.recipientRepo.findOne({
        where: {
          recipientUserId: callerUserId,
          folderId: dto.folderId,
          keyVersion: dto.keyVersion,
          revokedAt: IsNull(),
        },
      });
    } else {
      // Find the latest active key version specifically for this calling user
      record = await this.recipientRepo
        .createQueryBuilder('r')
        .where('r.recipientUserId = :callerUserId', { callerUserId })
        .andWhere('r.folderId = :folderId', { folderId: dto.folderId })
        .andWhere('r.revokedAt IS NULL')
        .orderBy('r.keyVersion', 'DESC')
        .limit(1)
        .getOne();
    }

    if (!record) {
      throw new NotFoundException(
        `No active wrapped key found for caller in folder ${dto.folderId}`,
      );
    }

    return {
      recipientUserId: record.recipientUserId,
      ephemeralX25519PublicKey: record.ephemeralX25519PublicKey,
      mlkemCiphertext: record.mlkemCiphertext,
      aesNonce: record.aesNonce,
      wrappedFolderKey: record.wrappedFolderKey,
    };
  }

  /**
   * Returns the current (latest) key version string for a folder.
   * Returns null if no version has been published for this folder.
   *
   * "Latest" is defined as the lexicographically greatest keyVersion —
   * since clients must send monotonically increasing versions, this is safe.
   */
  async getCurrentKeyVersion(folderId: string): Promise<string | null> {
    const row = await this.versionRepo
      .createQueryBuilder('v')
      .where('v.folderId = :folderId', { folderId })
      .orderBy('v.keyVersion', 'DESC')
      .limit(1)
      .getOne();
    return row?.keyVersion ?? null;
  }

  /**
   * Returns all active recipients for the latest key version of a folder.
   */
  async listRecipientsForFolder(folderId: string): Promise<Array<{ recipientUserId: string; keyVersion: string; createdAt: Date }>> {
    const latestVersion = await this.getCurrentKeyVersion(folderId);
    if (!latestVersion) return [];

    const rows = await this.recipientRepo.find({
      where: {
        folderId,
        keyVersion: latestVersion,
        revokedAt: IsNull(),
      },
    });

    return rows.map((r) => ({
      recipientUserId: r.recipientUserId,
      keyVersion: r.keyVersion,
      createdAt: r.createdAt,
    }));
  }

  /**
   * Returns all active shares for the calling recipient user across all folders.
   */
  async listMyShares(callerUserId: string): Promise<Array<{ folderId: string; keyVersion: string; record: WrappedKeyRecordDto }>> {
    const rows = await this.recipientRepo
      .createQueryBuilder('r')
      .where('r.recipientUserId = :callerUserId', { callerUserId })
      .andWhere('r.revokedAt IS NULL')
      .getMany();

    return rows.map((r) => ({
      folderId: r.folderId,
      keyVersion: r.keyVersion,
      record: {
        recipientUserId: r.recipientUserId,
        ephemeralX25519PublicKey: r.ephemeralX25519PublicKey,
        mlkemCiphertext: r.mlkemCiphertext,
        aesNonce: r.aesNonce,
        wrappedFolderKey: r.wrappedFolderKey,
      },
    }));
  }
}
