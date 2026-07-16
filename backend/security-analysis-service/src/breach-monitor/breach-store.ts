/**
 * BreachStore — TypeORM-backed persistence layer for opt-in breach monitoring.
 *
 * Replaces the former in-memory Map implementation so that:
 *  - Data survives process restarts.
 *  - The scheduler can iterate real opted-in rows from Postgres.
 *
 * Security invariants (unchanged from the original):
 *  - emailHash is the only key used for lookups — the raw email is NEVER
 *    stored in plaintext. We encrypt it with AES-256-GCM using the
 *    BREACH_ENCRYPTION_KEY environment variable before persisting.
 *  - Only breach metadata (name, breachDate, dataClasses) leaves this class.
 *  - The raw HIBP API response and the plaintext email address are never
 *    written to any storage layer.
 */
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as crypto from 'crypto';
import { BreachOptIn } from './entities/breach-opt-in.entity';
import { BreachEntry as BreachEntryEntity } from './entities/breach-entry.entity';

/** Shape of a breach metadata record — matches the existing contract. */
export interface BreachEntry {
  name: string;
  breachDate: string;
  dataClasses: string[];
}

// ── Email encryption helpers ──────────────────────────────────────────────────
// AES-256-GCM: key must be 32 bytes. We derive it from the env var using SHA-256
// so any printable string works as the env value.

const ALGORITHM = 'aes-256-gcm';
const IV_BYTES = 12;   // 96-bit nonce for GCM
const TAG_BYTES = 16;  // 128-bit auth tag

function deriveKey(): Buffer {
  const raw = process.env.BREACH_ENCRYPTION_KEY ?? 'dev-breach-key-CHANGE-IN-PROD';
  return crypto.createHash('sha256').update(raw).digest();
}

function encryptEmail(email: string): string {
  const key = deriveKey();
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv) as crypto.CipherGCM;
  const ct = Buffer.concat([cipher.update(email, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  // Format: <iv_hex>:<tag_hex>:<ciphertext_hex>
  return `${iv.toString('hex')}:${tag.toString('hex')}:${ct.toString('hex')}`;
}

function decryptEmail(stored: string): string {
  const parts = stored.split(':');
  if (parts.length !== 3) throw new Error('Invalid encrypted email format');
  const [ivHex, tagHex, ctHex] = parts;
  const key = deriveKey();
  const iv = Buffer.from(ivHex, 'hex');
  const tag = Buffer.from(tagHex, 'hex');
  const ct = Buffer.from(ctHex, 'hex');
  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv) as crypto.DecipherGCM;
  decipher.setAuthTag(tag);
  return decipher.update(ct).toString('utf8') + decipher.final('utf8');
}

// ── BreachStore ───────────────────────────────────────────────────────────────

@Injectable()
export class BreachStore implements OnModuleInit {
  private readonly logger = new Logger(BreachStore.name);

  constructor(
    @InjectRepository(BreachOptIn)
    private readonly optInRepo: Repository<BreachOptIn>,
    @InjectRepository(BreachEntryEntity)
    private readonly entryRepo: Repository<BreachEntryEntity>,
  ) {}

  onModuleInit(): void {
    const keyEnv = process.env.BREACH_ENCRYPTION_KEY;
    if (!keyEnv || keyEnv === 'dev-breach-key-CHANGE-IN-PROD') {
      this.logger.warn(
        'BREACH_ENCRYPTION_KEY is not set or is the dev placeholder. ' +
        'Set a strong random value in production.',
      );
    }
  }

  // ── Opt-in / Opt-out ───────────────────────────────────────────────────────

  /**
   * Records that [emailHash] has opted in.
   * The email is AES-256-GCM encrypted before it is written to the DB.
   * Upserts so that repeated opt-in calls are safe.
   */
  async optIn(emailHash: string, email: string): Promise<void> {
    const encryptedEmail = encryptEmail(email);
    await this.optInRepo
      .createQueryBuilder()
      .insert()
      .into(BreachOptIn)
      .values({ emailHash, encryptedEmail })
      .orUpdate(['encryptedEmail'], ['emailHash'])
      .execute();
  }

  /**
   * Removes [emailHash] from opt-in monitoring.
   * Cascade delete on the FK removes all associated BreachEntry rows.
   */
  async optOut(emailHash: string): Promise<void> {
    await this.optInRepo.delete({ emailHash });
  }

  /** Returns true if [emailHash] has an active opt-in row. */
  async isOptedIn(emailHash: string): Promise<boolean> {
    const count = await this.optInRepo.count({ where: { emailHash } });
    return count > 0;
  }

  /**
   * Returns the plaintext email for [emailHash] by decrypting the stored value.
   * Returns null if [emailHash] is not opted in.
   */
  async getEmail(emailHash: string): Promise<string | null> {
    const optIn = await this.optInRepo.findOne({ where: { emailHash } });
    if (!optIn) return null;
    try {
      return decryptEmail(optIn.encryptedEmail);
    } catch (err) {
      this.logger.error(`Failed to decrypt email for hash ${emailHash.slice(0, 8)}…`, err);
      return null;
    }
  }

  /** Returns every opted-in emailHash — used by the scheduler. */
  async allOptedInHashes(): Promise<string[]> {
    const rows = await this.optInRepo.find({ select: ['emailHash'] });
    return rows.map((r) => r.emailHash);
  }

  // ── Breach entries ─────────────────────────────────────────────────────────

  /** Returns all stored BreachEntry rows for [emailHash]. */
  async getBreaches(emailHash: string): Promise<BreachEntry[]> {
    const rows = await this.entryRepo.find({ where: { emailHash } });
    return rows.map(this.#toDto);
  }

  /**
   * Upserts incoming breaches by (emailHash, breachSource), keyed on 'hibp'.
   * Returns ONLY the entries that are new compared to what was already stored,
   * preserving the original diff behaviour of the in-memory implementation.
   *
   * The unique constraint on (emailHash, breachSource) means each breach source
   * can appear at most once per email hash.  For HIBP, breachSource='hibp:<name>'
   * so each named breach is a separate row.
   */
  async updateBreaches(emailHash: string, incoming: BreachEntry[]): Promise<BreachEntry[]> {
    if (incoming.length === 0) return [];

    // Build one row per incoming breach with breachSource = 'hibp:<name>'
    const candidates = incoming.map((b) => ({
      emailHash,
      breachSource: `hibp:${b.name}`,
      name: b.name,
      breachDate: b.breachDate,
      dataClasses: b.dataClasses,
    }));

    // Use INSERT … ON CONFLICT DO NOTHING to only insert truly new rows.
    // The query builder returns affected rows count.
    const result = await this.entryRepo
      .createQueryBuilder()
      .insert()
      .into(BreachEntryEntity)
      .values(candidates)
      .orIgnore()          // ON CONFLICT (emailHash, breachSource) DO NOTHING
      .returning(['name', 'breachDate', 'dataClasses'])
      .execute();

    // `raw` contains the rows that were actually inserted (the new ones).
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (result.raw as any[]).map((r) => ({
      name: r.name as string,
      breachDate: r.breachDate as string,
      dataClasses: (typeof r.dataClasses === 'string'
        ? r.dataClasses.split(',')
        : r.dataClasses) as string[],
    }));
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  readonly #toDto = (row: BreachEntryEntity): BreachEntry => ({
    name: row.name,
    breachDate: row.breachDate,
    dataClasses: Array.isArray(row.dataClasses) ? row.dataClasses : [],
  });
}
