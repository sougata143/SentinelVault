import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UserRepository, UserRecord } from './user.repository';
import { SrpServer } from './srp';
import { TotpHelper } from './totp';
import * as crypto from 'crypto';
import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
  VerifyRegistrationResponseOpts,
  VerifyAuthenticationResponseOpts,
} from '@simplewebauthn/server';
import { Repository, QueryFailedError } from 'typeorm';
import { InjectRepository } from '@nestjs/typeorm';
import { Logger } from '@nestjs/common';
import { RedisService } from './redis.service';
import { AuditService } from './audit.service';
import { SessionEntity } from './entities/session.entity';
import { parseDeviceLabel } from './utils/user-agent-parser';

interface LoginChallenge {
  username: string;
  A: bigint;
  b: bigint;
  B: bigint;
  salt: Buffer;
  verifier: bigint;
  createdAt: number;
}

interface MfaSession {
  username: string;
  createdAt: number;
}

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
export class AuthService {
  // Temporary storage for active MFA sessions, keyed by mfaToken
  private readonly mfaSessions: Map<string, MfaSession> = new Map();
  // Temporary storage for WebAuthn challenges, keyed by username
  private readonly webauthnChallenges: Map<string, { challenge: string; createdAt: number }> = new Map();
  // Temporary storage for primary passkey challenges, keyed by challenge string
  private readonly passkeyChallenges: Map<string, { username?: string; createdAt: number }> = new Map();
  // Server secret for generating deterministic dummy parameters for invalid users
  private readonly serverSecret: Buffer;
  private readonly logger = new Logger(AuthService.name);

  // WebAuthn configuration constants
  private readonly rpName = 'SentinelVault';
  private readonly rpID = 'localhost';
  private readonly origin = 'http://localhost:8181';

  constructor(
    private readonly userRepository: UserRepository,
    private readonly jwtService: JwtService,
    private readonly redisService: RedisService,
    private readonly auditService: AuditService,
    @InjectRepository(SessionEntity)
    private readonly sessionRepo: Repository<SessionEntity>,
  ) {
    this.serverSecret = crypto.randomBytes(32);
  }

  /**
   * Creates and persists a new user session upon successful authentication.
   */
  public async createSession(
    userId: string,
    username: string,
    loginMethod: string,
    userAgent?: string,
  ): Promise<{ session: SessionEntity; token: string }> {
    const deviceLabel = parseDeviceLabel(userAgent);
    const session = this.sessionRepo.create({
      userId,
      deviceLabel,
      loginMethod,
      isRevoked: false,
    });
    const savedSession = await this.sessionRepo.save(session);

    const token = this.jwtService.sign(
      { sub: userId, username, jti: savedSession.id },
      { expiresIn: '24h' },
    );

    savedSession.tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    await this.sessionRepo.save(savedSession);

    await this.auditService.logEvent({
      userId,
      eventType: 'session_created',
      userAgent,
      metadata: { sessionId: savedSession.id, deviceLabel, loginMethod },
    });

    return { session: savedSession, token };
  }

  /**
   * Retrieves active non-revoked sessions for a given user.
   */
  public async getUserSessions(
    userId: string,
    currentJti?: string,
  ): Promise<Array<{ id: string; deviceLabel: string; loginMethod: string; createdAt: Date; lastActiveAt: Date; isCurrent: boolean }>> {
    const sessions = await this.sessionRepo.find({
      where: { userId, isRevoked: false },
      order: { lastActiveAt: 'DESC' },
    });

    return sessions.map((s) => ({
      id: s.id,
      deviceLabel: s.deviceLabel,
      loginMethod: s.loginMethod,
      createdAt: s.createdAt,
      lastActiveAt: s.lastActiveAt,
      isCurrent: s.id === currentJti,
    }));
  }

  /**
   * Revokes a specific session for a user.
   */
  public async revokeSession(
    userId: string,
    currentJti: string | undefined,
    sessionIdToRevoke: string,
  ): Promise<{ success: boolean }> {
    if (currentJti && sessionIdToRevoke === currentJti) {
      throw new HttpException('Cannot revoke current session. Use standard logout flow.', HttpStatus.BAD_REQUEST);
    }

    const session = await this.sessionRepo.findOne({
      where: { id: sessionIdToRevoke, userId },
    });

    if (!session) {
      throw new HttpException('Session not found', HttpStatus.NOT_FOUND);
    }

    session.isRevoked = true;
    await this.sessionRepo.save(session);

    // Push jti to Redis denylist with 24 hour TTL
    await this.redisService.set(`revoked:jti:${sessionIdToRevoke}`, '1', 'EX', 86400);

    await this.auditService.logEvent({
      userId,
      eventType: 'session_revoked',
      metadata: { sessionId: sessionIdToRevoke, deviceLabel: session.deviceLabel },
    });

    return { success: true };
  }

  public async lookupUserByEmail(email: string): Promise<{ id: string; username: string } | null> {
    const user = await this.userRepository.findByUsername(email);
    if (!user || !user.id) return null;
    return { id: user.id, username: user.username };
  }

  public async lookupUserById(id: string): Promise<{ id: string; username: string } | null> {
    let user = await this.userRepository.findById(id);
    if (!user) {
      user = await this.userRepository.findByUsername(id);
    }
    if (!user || !user.id) return null;
    return { id: user.id, username: user.username };
  }

  /**
   * Registers a new user.
   */
  public async register(username: string, saltHex: string, verifierHex: string, userAgent?: string): Promise<{ success: boolean; token: string }> {
    const hrStart = process.hrtime.bigint();
    const isoStart = new Date().toISOString();
    // console.log(`[DIAG_REGISTER_START] ISO=${isoStart} HR=${hrStart} username=${username} saltFp=${fp(saltHex)} verifierFp=${fp(verifierHex)}`);

    if (!username || !saltHex || !verifierHex) {
      throw new HttpException('Missing registration parameters', HttpStatus.BAD_REQUEST);
    }

    let existing;
    try {
      existing = await this.userRepository.findByUsername(username);
    } catch (err) {
      this.logger.error('findByUsername failed', err instanceof Error ? err.stack : String(err));
      throw new HttpException('Registration failed. Please try again.', HttpStatus.INTERNAL_SERVER_ERROR);
    }

    if (existing) {
      throw new HttpException('Username already exists', HttpStatus.CONFLICT);
    }

    let saved: UserRecord & { id: string };
    try {
      saved = await this.userRepository.save({
        username,
        salt: saltHex,
        verifier: verifierHex,
        failedAttempts: 0,
        lockoutUntil: null,
        totpEnabled: false,
        webauthnEnabled: false,
      });
    } catch (err) {
      if (err instanceof QueryFailedError && (err as any).code === '23505') {
        throw new HttpException('Username already exists', HttpStatus.CONFLICT);
      }
      this.logger.error('User registration failed', err instanceof Error ? err.stack : String(err));
      throw new HttpException('Registration failed. Please try again.', HttpStatus.INTERNAL_SERVER_ERROR);
    }

    const hrEnd = process.hrtime.bigint();
    const elapsedMs = Number(hrEnd - hrStart) / 1e6;
    // console.log(`[DIAG_REGISTER_COMPLETE] ISO=${new Date().toISOString()} HR=${hrEnd} ELAPSED_MS=${elapsedMs.toFixed(3)} registeredUser=${saved.username} id=${saved.id} saltFp=${fp(saved.salt)} verifierFp=${fp(saved.verifier)}`);

    const { token } = await this.createSession(saved.id, saved.username, 'registration', userAgent);

    return { success: true, token };
  }

  /**
   * Initiates Login Step 1.
   * Checks for account lockout, generates challenge parameters.
   */
  public async loginStep1(
    username: string,
    aHex: string,
  ): Promise<{ salt: string; B: string; challengeId: string }> {
    const hrStart = process.hrtime.bigint();
    const isoStart = new Date().toISOString();
    // console.log(`[DIAG_STEP1_START] ISO=${isoStart} HR=${hrStart} username=${username} aFp=${fp(aHex)}`);

    if (!username || !aHex) {
      throw new HttpException('Missing login parameters', HttpStatus.BAD_REQUEST);
    }

    const user = await this.userRepository.findByUsername(username);
    const now = new Date();

    if (user && user.lockoutUntil && user.lockoutUntil > now) {
      throw new HttpException('Account is locked. Try again later.', 423);
    }

    let salt: Buffer;
    let v: bigint;

    if (user) {
      salt = Buffer.from(user.salt, 'hex');
      v = BigInt('0x' + user.verifier);
    } else {
      // User enumeration prevention: Generate deterministic dummy values for unknown users
      const dummySaltInput = Buffer.concat([Buffer.from(username.toLowerCase()), this.serverSecret]);
      const dummySaltHash = crypto.createHash('sha256').update(dummySaltInput).digest();
      salt = dummySaltHash.subarray(0, 16); // 16-byte salt

      const dummyVerifierInput = Buffer.concat([dummySaltHash, this.serverSecret]);
      const dummyVerifierHash = crypto.createHash('sha256').update(dummyVerifierInput).digest();
      v = BigInt('0x' + dummyVerifierHash.toString('hex')) % SrpServer.N;
    }

    const A = BigInt('0x' + aHex);
    const bBytes = crypto.randomBytes(32);
    const { secret: b, publicValue: B } = SrpServer.generateServerEphemeral(v, bBytes);

    const challengeId = crypto.randomBytes(16).toString('hex');
    const createdAt = Date.now();
    const redisKey = `srp:challenge:${challengeId}`;
    const challengeData = JSON.stringify({
      username,
      A: A.toString(16),
      b: b.toString(16),
      B: B.toString(16),
      salt: salt.toString('hex'),
      verifier: v.toString(16),
      createdAt,
    });

    // Store challenge in Redis with a 5-minute (300 seconds) native TTL
    await this.redisService.set(redisKey, challengeData, 'EX', 300);

    const hrEnd = process.hrtime.bigint();
    const elapsedMs = Number(hrEnd - hrStart) / 1e6;

    // console.log(`[DIAG_STEP1_CHALLENGE_CREATED] ISO=${new Date().toISOString()} HR=${hrEnd} ELAPSED_MS=${elapsedMs.toFixed(3)} challengeIdFp=${fp(challengeId)} username=${username} isRealUser=${!!user} saltFp=${fp(salt)} verifierFp=${fp(v)} AFp=${fp(A)} BFp=${fp(B)} bFp=${fp(b)} createdAt=${createdAt}`);

    // Clean up old non-Redis challenges
    this.pruneOldChallenges();

    return {
      salt: salt.toString('hex'),
      B: B.toString(16),
      challengeId,
    };
  }

  /**
   * Completes Login Step 2.
   * Verifies client proof (M1) and handles account lockout state increments.
   * If MFA is enabled, returns an MFA redirect instead of the final token.
   */
  public async loginStep2(challengeId: string, m1Hex: string, userAgent?: string): Promise<any> {
    const hrStart = process.hrtime.bigint();
    const isoStart = new Date().toISOString();
    // console.log(`[DIAG_STEP2_START] ISO=${isoStart} HR=${hrStart} challengeIdFp=${fp(challengeId)} m1Fp=${fp(m1Hex)}`);

    const redisKey = `srp:challenge:${challengeId}`;
    const rawChallenge = await this.redisService.getdel(redisKey);
    if (!rawChallenge) {
      // console.log(`[DIAG_STEP2_ERROR] ISO=${new Date().toISOString()} HR=${process.hrtime.bigint()} Challenge NOT FOUND: challengeIdFp=${fp(challengeId)}`);
      throw new HttpException('Invalid or expired login session', HttpStatus.UNAUTHORIZED);
    }

    const parsed = JSON.parse(rawChallenge);
    const challenge: LoginChallenge = {
      username: parsed.username,
      A: BigInt('0x' + parsed.A),
      b: BigInt('0x' + parsed.b),
      B: BigInt('0x' + parsed.B),
      salt: Buffer.from(parsed.salt, 'hex'),
      verifier: BigInt('0x' + parsed.verifier),
      createdAt: parsed.createdAt,
    };

    const challengeAgeMs = Date.now() - challenge.createdAt;
    // console.log(`[DIAG_STEP2_CHALLENGE_FOUND] ISO=${new Date().toISOString()} HR=${process.hrtime.bigint()} challengeIdFp=${fp(challengeId)} username=${challenge.username} challengeAgeMs=${challengeAgeMs}`);

    const user = await this.userRepository.findByUsername(challenge.username);
    const now = new Date();

    if (user && user.lockoutUntil && user.lockoutUntil > now) {
      throw new HttpException('Account is locked. Try again later.', 423);
    }

    const clientEvidence = Buffer.from(m1Hex, 'hex');
    const verification = SrpServer.verifySession({
      username: challenge.username,
      salt: challenge.salt,
      A: challenge.A,
      B: challenge.B,
      v: challenge.verifier,
      b: challenge.b,
      clientEvidence,
    });

    const hrEnd = process.hrtime.bigint();
    const elapsedMs = Number(hrEnd - hrStart) / 1e6;

    // console.log(`[DIAG_STEP2_VERIFY_RESULT] ISO=${new Date().toISOString()} HR=${hrEnd} ELAPSED_MS=${elapsedMs.toFixed(3)} success=${verification.success} username=${challenge.username} userFound=${!!user} userSaltFp=${fp(user?.salt)} challengeSaltFp=${fp(challenge.salt)} userVerifierFp=${fp(user?.verifier)} challengeVerifierFp=${fp(challenge.verifier)} saltMatches=${user?.salt === challenge.salt.toString('hex')} verifierMatches=${user?.verifier === challenge.verifier.toString(16)}`);

    if (!verification.success || !user) {
      if (user) {
        user.failedAttempts += 1;
        if (user.failedAttempts >= 5) {
          user.lockoutUntil = new Date(Date.now() + 15 * 60 * 1000);
        }
        await this.userRepository.save(user);
        await this.auditService.logEvent({
          userId: user.id,
          eventType: 'login_failure',
          metadata: { reason: 'invalid_credentials', attempts: user.failedAttempts },
        });
      } else {
        await this.auditService.logEvent({
          userId: challenge.username,
          eventType: 'login_failure',
          metadata: { reason: 'user_not_found' },
        });
      }
      throw new HttpException('Incorrect username or password', HttpStatus.UNAUTHORIZED);
    }

    // Successful password authentication: reset failed login attempts
    user.failedAttempts = 0;
    user.lockoutUntil = null;
    await this.userRepository.save(user);
    await this.auditService.logEvent({
      userId: user.id,
      eventType: 'login_success',
      metadata: { method: 'srp-6a' },
    });

    // ── MFA Gate ───────────────────────────────────────────────────────────
    if (user.totpEnabled || user.webauthnEnabled) {
      const mfaToken = crypto.randomBytes(32).toString('hex');
      this.mfaSessions.set(mfaToken, {
        username: user.username,
        createdAt: Date.now(),
      });

      const allowedMethods = [];
      if (user.totpEnabled) allowedMethods.push('totp');
      if (user.webauthnEnabled) allowedMethods.push('webauthn');

      return {
        mfaRequired: true,
        mfaToken,
        allowedMethods,
        serverEvidence: verification.serverEvidence!.toString('hex'),
      };
    }

    // No MFA enabled: issue a signed JWT as the final session token
    const { token } = await this.createSession(user.id!, user.username, 'srp-6a', userAgent);

    return {
      serverEvidence: verification.serverEvidence!.toString('hex'),
      token,
    };
  }

  // ── TOTP MFA Endpoints ──────────────────────────────────────────────────

  public async generateTotp(username: string): Promise<{ secret: string; provisioningUri: string }> {
    const user = await this.userRepository.findByUsername(username);
    if (!user) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }

    const secret = TotpHelper.generateSecret();
    user.totpSecret = secret;
    await this.userRepository.save(user);

    const provisioningUri = TotpHelper.getProvisioningUri(user.username, secret);
    return { secret, provisioningUri };
  }

  public async enableTotp(username: string, code: string): Promise<{ success: boolean }> {
    const user = await this.userRepository.findByUsername(username);
    if (!user || !user.totpSecret) {
      throw new HttpException('TOTP not setup', HttpStatus.BAD_REQUEST);
    }

    const isValid = TotpHelper.verifyCode(user.totpSecret, code);
    if (!isValid) {
      throw new HttpException('Invalid code', HttpStatus.UNAUTHORIZED);
    }

    user.totpEnabled = true;
    await this.userRepository.save(user);
    return { success: true };
  }

  public async verifyTotp(mfaToken: string, code: string, userAgent?: string): Promise<{ token: string }> {
    const session = this.mfaSessions.get(mfaToken);
    if (!session || session.createdAt < Date.now() - 5 * 60 * 1000) {
      throw new HttpException('Invalid or expired MFA session', HttpStatus.UNAUTHORIZED);
    }

    const user = await this.userRepository.findByUsername(session.username);
    if (!user || !user.totpEnabled || !user.totpSecret) {
      throw new HttpException('TOTP is not enabled', HttpStatus.BAD_REQUEST);
    }

    const isValid = TotpHelper.verifyCode(user.totpSecret, code);
    if (!isValid) {
      throw new HttpException('Invalid code', HttpStatus.UNAUTHORIZED);
    }

    // MFA succeeded: clear session and issue a signed JWT
    this.mfaSessions.delete(mfaToken);
    const { token } = await this.createSession(user.id!, user.username, 'mfa_totp', userAgent);
    return { token };
  }

  // ── WebAuthn MFA Endpoints ──────────────────────────────────────────────

  public async generateWebAuthnRegisterOptions(username: string): Promise<any> {
    const user = await this.userRepository.findByUsername(username);
    if (!user) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }

    const options = await generateRegistrationOptions({
      rpName: this.rpName,
      rpID: this.rpID,
      userID: Buffer.from(user.username),
      userName: user.username,
      attestationType: 'none',
      authenticatorSelection: {
        residentKey: 'required',
        userVerification: 'preferred',
      },
    });

    this.webauthnChallenges.set(user.username.toLowerCase(), {
      challenge: options.challenge,
      createdAt: Date.now(),
    });

    return options;
  }

  public async verifyWebAuthnRegister(username: string, response: any): Promise<{ success: boolean }> {
    const user = await this.userRepository.findByUsername(username);
    if (!user) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }

    const challengeRecord = this.webauthnChallenges.get(user.username.toLowerCase());
    if (!challengeRecord || challengeRecord.createdAt < Date.now() - 5 * 60 * 1000) {
      throw new HttpException('Invalid or expired registration challenge', HttpStatus.BAD_REQUEST);
    }
    this.webauthnChallenges.delete(user.username.toLowerCase());

    const opts: VerifyRegistrationResponseOpts = {
      response,
      expectedChallenge: challengeRecord.challenge,
      expectedOrigin: this.origin,
      expectedRPID: this.rpID,
    };

    const verification = await verifyRegistrationResponse(opts);

    if (!verification.verified || !verification.registrationInfo) {
      throw new HttpException('WebAuthn registration verification failed', HttpStatus.BAD_REQUEST);
    }

    const { credential } = verification.registrationInfo;

    user.webauthnCredentials = user.webauthnCredentials || [];
    user.webauthnCredentials.push({
      credentialID: credential.id,
      publicKey: Buffer.from(credential.publicKey).toString('base64url'),
      counter: credential.counter,
    });
    user.webauthnEnabled = true;

    await this.userRepository.save(user);
    return { success: true };
  }

  public async generateWebAuthnLoginOptions(mfaToken: string): Promise<any> {
    const session = this.mfaSessions.get(mfaToken);
    if (!session || session.createdAt < Date.now() - 5 * 60 * 1000) {
      throw new HttpException('Invalid or expired MFA session', HttpStatus.UNAUTHORIZED);
    }

    const user = await this.userRepository.findByUsername(session.username);
    if (!user || !user.webauthnEnabled || !user.webauthnCredentials) {
      throw new HttpException('WebAuthn is not enabled for this account', HttpStatus.BAD_REQUEST);
    }

    const options = await generateAuthenticationOptions({
      rpID: this.rpID,
      allowCredentials: user.webauthnCredentials.map((cred) => ({
        id: cred.credentialID,
        type: 'public-key',
        transports: cred.transports as any,
      })),
    });

    this.webauthnChallenges.set(user.username.toLowerCase(), {
      challenge: options.challenge,
      createdAt: Date.now(),
    });

    return options;
  }

  public async verifyWebAuthnLogin(mfaToken: string, response: any, userAgent?: string): Promise<{ token: string }> {
    const session = this.mfaSessions.get(mfaToken);
    if (!session || session.createdAt < Date.now() - 5 * 60 * 1000) {
      throw new HttpException('Invalid or expired MFA session', HttpStatus.UNAUTHORIZED);
    }

    const user = await this.userRepository.findByUsername(session.username);
    if (!user || !user.webauthnEnabled || !user.webauthnCredentials) {
      throw new HttpException('WebAuthn not configured', HttpStatus.BAD_REQUEST);
    }

    const challengeRecord = this.webauthnChallenges.get(user.username.toLowerCase());
    if (!challengeRecord || challengeRecord.createdAt < Date.now() - 5 * 60 * 1000) {
      throw new HttpException('Invalid or expired authentication challenge', HttpStatus.BAD_REQUEST);
    }
    this.webauthnChallenges.delete(user.username.toLowerCase());

    const cred = user.webauthnCredentials.find(
      (c) => c.credentialID === response.id,
    );
    if (!cred) {
      throw new HttpException('Credential not recognized for this user', HttpStatus.UNAUTHORIZED);
    }

    const opts: VerifyAuthenticationResponseOpts = {
      response,
      expectedChallenge: challengeRecord.challenge,
      expectedOrigin: this.origin,
      expectedRPID: this.rpID,
      credential: {
        id: cred.credentialID,
        publicKey: Buffer.from(cred.publicKey, 'base64url'),
        counter: cred.counter,
        transports: cred.transports as any,
      },
    };

    const verification = await verifyAuthenticationResponse(opts);

    if (!verification.verified || !verification.authenticationInfo) {
      throw new HttpException('WebAuthn login verification failed', HttpStatus.UNAUTHORIZED);
    }

    // Update credential counter
    cred.counter = verification.authenticationInfo.newCounter;
    await this.userRepository.save(user);

    // MFA succeeded: clear session and issue a signed JWT
    this.mfaSessions.delete(mfaToken);
    const { token } = await this.createSession(user.id!, user.username, 'mfa_webauthn', userAgent);
    return { token };
  }

  // ── Primary Passkey Endpoints ──────────────────────────────────────────

  public async generatePasskeyRegisterOptions(username: string): Promise<any> {
    return await this.generateWebAuthnRegisterOptions(username);
  }

  public async verifyPasskeyRegister(username: string, response: any): Promise<{ success: boolean }> {
    return await this.verifyWebAuthnRegister(username, response);
  }

  public async generatePasskeyLoginOptions(username?: string): Promise<any> {
    let allowCredentials = undefined;

    if (username) {
      const user = await this.userRepository.findByUsername(username);
      if (!user || !user.webauthnCredentials || user.webauthnCredentials.length === 0) {
        throw new HttpException('Passkey login not set up for this user', HttpStatus.BAD_REQUEST);
      }
      allowCredentials = user.webauthnCredentials.map((cred) => ({
        id: cred.credentialID,
        type: 'public-key' as const,
        transports: cred.transports as any,
      }));
    }

    const options = await generateAuthenticationOptions({
      rpID: this.rpID,
      allowCredentials,
      userVerification: 'preferred',
    });

    this.passkeyChallenges.set(options.challenge, {
      username: username ? username.toLowerCase() : undefined,
      createdAt: Date.now(),
    });

    // Clean up old challenges
    this.pruneOldChallenges();

    return options;
  }

  public async verifyPasskeyLogin(challenge: string, response: any, userAgent?: string): Promise<{ token: string }> {
    if (!challenge) {
      throw new HttpException('Missing challenge parameter', HttpStatus.BAD_REQUEST);
    }
    const challengeRecord = this.passkeyChallenges.get(challenge);
    if (!challengeRecord || challengeRecord.createdAt < Date.now() - 5 * 60 * 1000) {
      throw new HttpException('Invalid or expired login challenge', HttpStatus.BAD_REQUEST);
    }
    this.passkeyChallenges.delete(challenge);

    let user: UserRecord | null = null;
    if (challengeRecord.username) {
      user = await this.userRepository.findByUsername(challengeRecord.username);
    } else {
      user = await this.userRepository.findByCredentialId(response.id);
    }

    if (!user || !user.webauthnCredentials) {
      throw new HttpException('User or passkey credential not found', HttpStatus.UNAUTHORIZED);
    }

    const cred = user.webauthnCredentials.find((c) => c.credentialID === response.id);
    if (!cred) {
      throw new HttpException('Credential not recognized for this user', HttpStatus.UNAUTHORIZED);
    }

    const opts: VerifyAuthenticationResponseOpts = {
      response,
      expectedChallenge: challenge,
      expectedOrigin: this.origin,
      expectedRPID: this.rpID,
      credential: {
        id: cred.credentialID,
        publicKey: Buffer.from(cred.publicKey, 'base64url'),
        counter: cred.counter,
        transports: cred.transports as any,
      },
    };

    const verification = await verifyAuthenticationResponse(opts);

    if (!verification.verified || !verification.authenticationInfo) {
      throw new HttpException('WebAuthn login verification failed', HttpStatus.UNAUTHORIZED);
    }

    // Update credential counter
    cred.counter = verification.authenticationInfo.newCounter;
    await this.userRepository.save(user);

    const { token } = await this.createSession(user.id!, user.username, 'passkey', userAgent);
    return { token };
  }

  /**
   * Deletes challenge sessions older than 5 minutes.
   */
  private pruneOldChallenges(): void {
    const fiveMinutesAgo = Date.now() - 5 * 60 * 1000;

    const staleMfa = [...this.mfaSessions.entries()]
      .filter(([, s]) => s.createdAt < fiveMinutesAgo)
      .map(([token]) => token);
    staleMfa.forEach(token => this.mfaSessions.delete(token));

    const stalePasskey = [...this.passkeyChallenges.entries()]
      .filter(([, s]) => s.createdAt < fiveMinutesAgo)
      .map(([ch]) => ch);
    stalePasskey.forEach(ch => this.passkeyChallenges.delete(ch));
  }

  public async getAuditLogs(
    userId: string,
    eventType?: string,
    limit = 50,
    offset = 0,
  ): Promise<{ events: any[]; total: number }> {
    return await this.auditService.getUserAuditLogs(userId, eventType, limit, offset);
  }

  public async recordAuditEvent(
    userId: string,
    eventType: string,
    metadata?: Record<string, any>,
  ): Promise<any> {
    return await this.auditService.logEvent({ userId, eventType, metadata });
  }
}

