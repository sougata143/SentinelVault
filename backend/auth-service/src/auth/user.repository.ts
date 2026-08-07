import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './entities/user.entity';
import { WebauthnCredential } from './entities/webauthn-credential.entity';
import * as crypto from 'crypto';
import * as os from 'os';

export interface UserRecord {
  /** UUID stable identifier. Always present on persisted records. */
  id: string;
  username: string;
  salt: string; // Hex string representation
  verifier: string; // Hex string representation of BigInt verifier
  failedAttempts: number;
  lockoutUntil: Date | null;
  // TOTP configuration
  totpSecret?: string;
  totpEnabled: boolean;
  // WebAuthn configuration
  webauthnEnabled: boolean;
  webauthnCredentials?: Array<{
    credentialID: string;
    publicKey: string; // base64url or hex format
    counter: number;
    transports?: string[];
  }>;
}

export type CreateUserDto = Omit<UserRecord, 'id'> & { id?: string };

function fp(val: string | Buffer | bigint | null | undefined): string {
  if (val === null || val === undefined) return 'null';
  let str: string;
  if (typeof val === 'bigint') {
    str = val.toString(16);
  } else if (Buffer.isBuffer(val)) {
    str = val.toString('hex');
  } else {
    str = String(val);
  }
  return crypto.createHash('sha256').update(str).digest('hex').substring(0, 6);
}

@Injectable()
export class UserRepository {
  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
    @InjectRepository(WebauthnCredential)
    private readonly webauthnCredentialRepository: Repository<WebauthnCredential>,
  ) {}

  private getPoolStats(): string {
    try {
      const driver = (this.userRepository.manager?.connection?.driver as any);
      const pool = driver?.master ?? driver?.pool;
      if (pool) {
        const total = pool.totalCount ?? pool.pool?.size ?? 'N/A';
        const idle = pool.idleCount ?? pool.pool?.available ?? 'N/A';
        const waiting = pool.waitingCount ?? pool.pool?.pending ?? 'N/A';
        return `pool[total=${total}, idle=${idle}, waiting=${waiting}]`;
      }
    } catch (_) {}
    return 'pool[N/A]';
  }

  private mapUserToRecord(user: User): UserRecord {
    return {
      id: user.id,
      username: user.username,
      salt: user.salt,
      verifier: user.verifier,
      failedAttempts: user.failedAttempts,
      lockoutUntil: user.lockoutUntil,
      totpSecret: user.totpSecret || undefined,
      totpEnabled: user.totpEnabled,
      webauthnEnabled: user.webauthnEnabled,
      webauthnCredentials: user.webauthnCredentials?.map((c) => ({
        credentialID: c.credentialID,
        publicKey: c.publicKey,
        counter: typeof c.counter === 'string' ? parseInt(c.counter, 10) : c.counter,
        transports: c.transports,
      })),
    };
  }

  /**
   * Finds a user record by their username (case-insensitive).
   */
  public async findByUsername(username: string): Promise<UserRecord | null> {
    const hrStart = process.hrtime.bigint();
    const isoStart = new Date().toISOString();
    const cpus = os.cpus().length;
    const poolInfo = this.getPoolStats();

    const user = await this.userRepository
      .createQueryBuilder('user')
      .leftJoinAndSelect('user.webauthnCredentials', 'credentials')
      .where('LOWER(user.username) = LOWER(:username)', { username })
      .getOne();

    const hrEnd = process.hrtime.bigint();
    const elapsedMs = Number(hrEnd - hrStart) / 1e6;

    // console.log(`[DIAG_DB_READ] ISO=${isoStart} HR_START=${hrStart} HR_END=${hrEnd} ELAPSED_MS=${elapsedMs.toFixed(3)} CPU_CORES=${cpus} ${poolInfo} findByUsername('${username}') => found=${!!user} saltFp=${fp(user?.salt)} verifierFp=${fp(user?.verifier)}`);

    if (!user) return null;
    return this.mapUserToRecord(user);
  }

  /**
   * Finds a user record by their stable UUID id.
   */
  public async findById(id: string): Promise<UserRecord | null> {
    const user = await this.userRepository.findOne({ where: { id } });
    if (!user) return null;
    return this.mapUserToRecord(user);
  }

  /**
   * Saves or updates a user record.
   * If the record has no `id` yet, a new UUID v4 is generated and persisted.
   * Returns the saved record with `id` guaranteed to be populated.
   */
  public async save(record: CreateUserDto | UserRecord): Promise<UserRecord> {
    const hrStart = process.hrtime.bigint();
    const isoStart = new Date().toISOString();
    const cpus = os.cpus().length;
    const poolInfo = this.getPoolStats();

    // Look up any existing user by username case-insensitively
    const existing = await this.userRepository
      .createQueryBuilder('user')
      .leftJoinAndSelect('user.webauthnCredentials', 'credentials')
      .where('LOWER(user.username) = LOWER(:username)', { username: record.username })
      .getOne();

    const id = record.id ?? existing?.id ?? crypto.randomUUID();

    const userEntity = existing ?? new User();
    userEntity.id = id;
    userEntity.username = record.username;
    userEntity.salt = record.salt;
    userEntity.verifier = record.verifier;
    userEntity.failedAttempts = record.failedAttempts;
    userEntity.lockoutUntil = record.lockoutUntil;
    userEntity.totpSecret = record.totpSecret || undefined;
    userEntity.totpEnabled = record.totpEnabled;
    userEntity.webauthnEnabled = record.webauthnEnabled;

    if (record.webauthnCredentials) {
      userEntity.webauthnCredentials = record.webauthnCredentials.map((c) => {
        const cred = new WebauthnCredential();
        cred.credentialID = c.credentialID;
        cred.publicKey = c.publicKey;
        cred.counter = typeof c.counter === 'string' ? parseInt(c.counter, 10) : c.counter;
        cred.transports = c.transports;
        cred.userId = id;
        return cred;
      });
    }

    const savedEntity = await this.userRepository.save(userEntity);
    const hrEnd = process.hrtime.bigint();
    const elapsedMs = Number(hrEnd - hrStart) / 1e6;

    // console.log(`[DIAG_DB_WRITE] ISO=${isoStart} HR_START=${hrStart} HR_END=${hrEnd} ELAPSED_MS=${elapsedMs.toFixed(3)} CPU_CORES=${cpus} ${poolInfo} save('${record.username}') => savedId=${savedEntity.id} saltFp=${fp(savedEntity.salt)} verifierFp=${fp(savedEntity.verifier)}`);
    return this.mapUserToRecord(savedEntity);
  }

  /**
   * Finds a user record by a registered credential ID.
   */
  public async findByCredentialId(credentialId: string): Promise<UserRecord | null> {
    const cred = await this.webauthnCredentialRepository.findOne({
      where: { credentialID: credentialId },
      relations: ['user', 'user.webauthnCredentials'],
    });

    if (!cred || !cred.user) return null;
    return this.mapUserToRecord(cred.user);
  }

  /**
   * Resets all user records (used for test cleanup).
   */
  public async clear(): Promise<void> {
    const hrStart = process.hrtime.bigint();
    const isoStart = new Date().toISOString();
    const cpus = os.cpus().length;
    await this.webauthnCredentialRepository.createQueryBuilder().delete().execute();
    await this.userRepository.createQueryBuilder().delete().execute();
    const hrEnd = process.hrtime.bigint();
    const elapsedMs = Number(hrEnd - hrStart) / 1e6;
    // console.log(`[DIAG_DB_CLEAR] ISO=${isoStart} HR_START=${hrStart} HR_END=${hrEnd} ELAPSED_MS=${elapsedMs.toFixed(3)} CPU_CORES=${cpus} UserRepository clear() completed`);
  }
}
