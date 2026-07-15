import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
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
import { Logger } from '@nestjs/common';

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

@Injectable()
export class AuthService {
  // Temporary storage for active login challenges, keyed by challengeId
  private readonly challenges: Map<string, LoginChallenge> = new Map();
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

  constructor(private readonly userRepository: UserRepository) {
    this.serverSecret = crypto.randomBytes(32);
  }

  /**
   * Registers a new user.
   */
  public async register(username: string, saltHex: string, verifierHex: string): Promise<{ success: boolean }> {
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

    try {
      await this.userRepository.save({
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

    return { success: true };
  }

  /**
   * Initiates Login Step 1.
   * Checks for account lockout, generates challenge parameters.
   */
  public async loginStep1(
    username: string,
    aHex: string,
  ): Promise<{ salt: string; B: string; challengeId: string }> {
    if (!username || !aHex) {
      throw new HttpException('Missing login parameters', HttpStatus.BAD_REQUEST);
    }

    const user = await this.userRepository.findByUsername(username);
    const now = new Date();

    // Check account lockout
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
    this.challenges.set(challengeId, {
      username,
      A,
      b,
      B,
      salt,
      verifier: v,
      createdAt: Date.now(),
    });

    // Clean up old challenges after 5 minutes
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
  public async loginStep2(challengeId: string, m1Hex: string): Promise<any> {
    const challenge = this.challenges.get(challengeId);
    if (!challenge) {
      throw new HttpException('Invalid or expired login session', HttpStatus.UNAUTHORIZED);
    }

    // Immediately remove challenge so it cannot be re-used (replay protection)
    this.challenges.delete(challengeId);

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

    if (!verification.success || !user) {
      // Handle authentication failure
      if (user) {
        user.failedAttempts += 1;
        if (user.failedAttempts >= 5) {
          // Lock account for 15 minutes
          user.lockoutUntil = new Date(Date.now() + 15 * 60 * 1000);
        }
        await this.userRepository.save(user);
      }
      throw new HttpException('Incorrect username or password', HttpStatus.UNAUTHORIZED);
    }

    // Successful password authentication: reset failed login attempts
    user.failedAttempts = 0;
    user.lockoutUntil = null;
    await this.userRepository.save(user);

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

    // No MFA enabled: return the final session token directly
    const token = crypto.randomBytes(32).toString('hex');

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

  public async verifyTotp(mfaToken: string, code: string): Promise<{ token: string }> {
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

    // MFA succeeded: clear session and return final token
    this.mfaSessions.delete(mfaToken);
    const token = crypto.randomBytes(32).toString('hex');
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

  public async verifyWebAuthnLogin(mfaToken: string, response: any): Promise<{ token: string }> {
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

    // MFA succeeded: clear session and return final token
    this.mfaSessions.delete(mfaToken);
    const token = crypto.randomBytes(32).toString('hex');
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

  public async verifyPasskeyLogin(challenge: string, response: any): Promise<{ token: string }> {
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

    const token = crypto.randomBytes(32).toString('hex');
    return { token };
  }

  /**
   * Deletes challenge sessions older than 5 minutes.
   */
  private pruneOldChallenges(): void {
    const fiveMinutesAgo = Date.now() - 5 * 60 * 1000;
    for (const [id, challenge] of this.challenges.entries()) {
      if (challenge.createdAt < fiveMinutesAgo) {
        this.challenges.delete(id);
      }
    }
    for (const [token, session] of this.mfaSessions.entries()) {
      if (session.createdAt < fiveMinutesAgo) {
        this.mfaSessions.delete(token);
      }
    }
    for (const [challenge, session] of this.passkeyChallenges.entries()) {
      if (session.createdAt < fiveMinutesAgo) {
        this.passkeyChallenges.delete(challenge);
      }
    }
  }
}

