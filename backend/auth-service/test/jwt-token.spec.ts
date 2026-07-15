/**
 * jwt-token.spec.ts
 *
 * Unit-level tests for the JWT tokens issued by AuthService.
 * Verifies that:
 *   1. A token returned by loginStep2 is a valid signed JWT.
 *   2. The decoded payload contains the correct `sub` (user id) and `username`.
 *   3. jwt.verify() succeeds with the correct secret.
 *   4. jwt.verify() throws with an incorrect secret.
 *
 * These tests run entirely in-process — no Postgres, no Redis — using the
 * NestJS test harness with the in-memory UserRepository.
 */
import { Test, TestingModule } from '@nestjs/testing';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { AuthService } from '../src/auth/auth.service';
import { UserRepository } from '../src/auth/user.repository';
import { SrpServer, bigIntToBuffer, bufferToBigInt, sha256 } from '../src/auth/srp';
import * as crypto from 'crypto';
import * as jwt from 'jsonwebtoken';

// Stub WebAuthn — not needed for these tests
jest.mock('@simplewebauthn/server', () => ({
  generateRegistrationOptions: jest.fn(),
  verifyRegistrationResponse: jest.fn(),
  generateAuthenticationOptions: jest.fn(),
  verifyAuthenticationResponse: jest.fn(),
}));

const TEST_SECRET = 'test-jwt-secret-at-least-32-bytes-long!!';

// ── SRP client helpers (copied from integration spec) ──────────────────────

async function computeClientX(user: string, pass: string, salt: Buffer): Promise<bigint> {
  const masterKeyBytes = Buffer.from(pass, 'utf-8');
  const identity = Buffer.from(`${user}:${masterKeyBytes.toString('hex')}`, 'utf-8');
  const innerHash = sha256(identity);
  const outerHash = sha256(Buffer.concat([salt, innerHash]));
  return bufferToBigInt(outerHash);
}

async function computeClientRegister(user: string, pass: string, salt: Buffer) {
  const x = await computeClientX(user, pass, salt);
  const v = SrpServer.modPow(SrpServer.g, x, SrpServer.N);
  return { saltHex: salt.toString('hex'), verifierHex: v.toString(16) };
}

async function computeM1(
  user: string,
  pass: string,
  salt: Buffer,
  B: bigint,
  a: bigint,
  A: bigint,
): Promise<{ m1Hex: string }> {
  const k = SrpServer.getMultiplierK();
  const x = await computeClientX(user, pass, salt);
  const u = SrpServer.calculateU(A, B);
  const exp = a + u * x;
  const gx = SrpServer.modPow(SrpServer.g, x, SrpServer.N);
  const base = (B - ((k * gx) % SrpServer.N) + SrpServer.N) % SrpServer.N;
  const S = SrpServer.modPow(base, exp, SrpServer.N);
  const sessionKey = sha256(bigIntToBuffer(S, 256));

  const hn = sha256(bigIntToBuffer(SrpServer.N, 256));
  const hg = sha256(bigIntToBuffer(SrpServer.g, 256));
  const hXor = Buffer.alloc(32);
  for (let i = 0; i < 32; i++) hXor[i] = hn[i] ^ hg[i];

  const hu = sha256(Buffer.from(user, 'utf-8'));
  const aBytes = bigIntToBuffer(A, 256);
  const bBytes = bigIntToBuffer(B, 256);
  const m1 = sha256(Buffer.concat([hXor, hu, salt, aBytes, bBytes, sessionKey]));
  return { m1Hex: m1.toString('hex') };
}

// ── Test suite ─────────────────────────────────────────────────────────────

describe('JWT token issued by AuthService', () => {
  let authService: AuthService;
  let jwtService: JwtService;
  let userRepository: UserRepository;

  const USERNAME = 'jwt_test_user';
  const PASSWORD = 'test_master_password';

  beforeAll(async () => {
    // Override JWT_SECRET so tests are hermetic (never rely on a .env value)
    process.env.JWT_SECRET = TEST_SECRET;

    const module: TestingModule = await Test.createTestingModule({
      imports: [
        JwtModule.register({
          secret: TEST_SECRET,
          signOptions: { expiresIn: '24h' },
        }),
      ],
      providers: [AuthService, UserRepository],
    }).compile();

    authService = module.get<AuthService>(AuthService);
    jwtService = module.get<JwtService>(JwtService);
    userRepository = module.get<UserRepository>(UserRepository);
  });

  beforeEach(async () => {
    await userRepository.clear();
  });

  /** Perform a full SRP register + login and return the issued token. */
  async function registerAndLogin(): Promise<string> {
    const saltBytes = crypto.randomBytes(16);
    const { saltHex, verifierHex } = await computeClientRegister(USERNAME, PASSWORD, saltBytes);
    await authService.register(USERNAME, saltHex, verifierHex);

    const aBytes = crypto.randomBytes(32);
    const a = bufferToBigInt(aBytes) % SrpServer.N;
    const A = SrpServer.modPow(SrpServer.g, a, SrpServer.N);

    const { salt: rcvSaltHex, B: rcvBHex, challengeId } =
      await authService.loginStep1(USERNAME, A.toString(16));

    const rcvB = BigInt('0x' + rcvBHex);
    const { m1Hex } = await computeM1(
      USERNAME,
      PASSWORD,
      Buffer.from(rcvSaltHex, 'hex'),
      rcvB,
      a,
      A,
    );

    const result = await authService.loginStep2(challengeId, m1Hex);
    return result.token as string;
  }

  it('token is a three-segment JWT string', async () => {
    const token = await registerAndLogin();
    expect(typeof token).toBe('string');
    // A JWT always has exactly three base64url segments separated by dots
    expect(token.split('.')).toHaveLength(3);
  });

  it('decoded payload contains the correct username', async () => {
    const token = await registerAndLogin();
    // Decode without verification to inspect the payload shape
    const payload = jwtService.decode(token) as Record<string, unknown>;
    expect(payload).toBeTruthy();
    expect(payload['username']).toBe(USERNAME);
  });

  it('decoded payload sub matches the stored user id (UUID)', async () => {
    const token = await registerAndLogin();
    const payload = jwtService.decode(token) as Record<string, unknown>;

    // Retrieve the stored user to confirm the id round-trips correctly
    const storedUser = await userRepository.findByUsername(USERNAME);
    expect(storedUser).not.toBeNull();
    expect(payload['sub']).toBe(storedUser!.id);
    // sub should be a valid UUID v4
    expect(payload['sub']).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  it('jwt.verify() succeeds with the correct secret', async () => {
    const token = await registerAndLogin();
    expect(() => jwt.verify(token, TEST_SECRET)).not.toThrow();

    const verified = jwt.verify(token, TEST_SECRET) as jwt.JwtPayload;
    expect(verified['username']).toBe(USERNAME);
  });

  it('jwt.verify() throws JsonWebTokenError with an incorrect secret', async () => {
    const token = await registerAndLogin();
    expect(() => jwt.verify(token, 'wrong-secret')).toThrow(jwt.JsonWebTokenError);
  });

  it('token carries a future expiry (exp claim is ~24 h from now)', async () => {
    const before = Math.floor(Date.now() / 1000);
    const token = await registerAndLogin();
    const after = Math.floor(Date.now() / 1000);

    const payload = jwtService.decode(token) as Record<string, unknown>;
    const exp = payload['exp'] as number;
    const iat = payload['iat'] as number;

    expect(iat).toBeGreaterThanOrEqual(before);
    expect(iat).toBeLessThanOrEqual(after);
    // expiresIn: '24h' → exp should be iat + 86400 (±5 s tolerance)
    expect(exp - iat).toBeGreaterThanOrEqual(86395);
    expect(exp - iat).toBeLessThanOrEqual(86405);
  });
});
