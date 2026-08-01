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
import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
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
    const bundle = await this.keyBundleRepo.findOne({ where: { userId } });
    if (!bundle) {
      throw new NotFoundException(`No key bundle found for user ${userId}`);
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
    // Monotonic version check — new version must be strictly greater than latest
    const latestVersion = await this.getCurrentKeyVersion(dto.folderId);
    if (latestVersion !== null && dto.keyVersion <= latestVersion) {
      throw new ConflictException(
        `Key version ${dto.keyVersion} is not greater than current version ${latestVersion}`,
      );
    }

    // Insert the new version row
    const version = this.versionRepo.create({
      folderId: dto.folderId,
      keyVersion: dto.keyVersion,
      publishedAt: new Date(),
    });
    await this.versionRepo.save(version);

    // Insert one recipient row per entry
    const recipientRows = dto.recipients.map((rec) =>
      this.recipientRepo.create({
        recipientUserId: rec.recipientUserId,
        folderId: dto.folderId,
        keyVersion: dto.keyVersion,
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

    await this.publishWrappedKeys(ownerUserId, {
      folderId: dto.folderId,
      keyVersion: dto.newKeyVersion,
      recipients: dto.remainingRecipients,
    });
  }

  /**
   * Fetches the wrapped Folder Key record for the authenticated calling user.
   * Returns the requested version, or the latest if not specified.
   *
   * Security: each recipient only receives their own wrapped record —
   * the server never returns another user's wrapped copy.
   */
  async fetchWrappedKey(
    callerUserId: string,
    dto: FetchWrappedKeyDto,
  ): Promise<WrappedKeyRecordDto> {
    let targetKeyVersion: string;

    if (dto.keyVersion !== undefined) {
      // Verify the requested version exists
      const version = await this.versionRepo.findOne({
        where: { folderId: dto.folderId, keyVersion: dto.keyVersion },
      });
      if (!version) {
        throw new NotFoundException(
          `Key version ${dto.keyVersion} not found for folder ${dto.folderId}`,
        );
      }
      targetKeyVersion = dto.keyVersion;
    } else {
      // Fetch the latest version
      const latest = await this.getCurrentKeyVersion(dto.folderId);
      if (latest === null) {
        throw new NotFoundException(
          `No wrapped keys found for folder ${dto.folderId}`,
        );
      }
      targetKeyVersion = latest;
    }

    // Fetch the specific recipient row — enforces per-caller security
    const record = await this.recipientRepo.findOne({
      where: {
        recipientUserId: callerUserId,
        folderId: dto.folderId,
        keyVersion: targetKeyVersion,
      },
    });
    if (!record) {
      throw new NotFoundException(
        `No wrapped key found for caller in folder ${dto.folderId} version ${targetKeyVersion}`,
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
}
