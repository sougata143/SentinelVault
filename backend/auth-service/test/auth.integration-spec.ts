import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, HttpStatus } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { UserRepository } from '../src/auth/user.repository';
import { SrpServer, bigIntToBuffer, bufferToBigInt, sha256 } from '../src/auth/srp';
import * as crypto from 'crypto';

// Mock WebAuthn library for predictable testing in Jest environment
jest.mock('@simplewebauthn/server', () => ({
  generateRegistrationOptions: jest.fn().mockResolvedValue({
    challenge: 'mock-reg-challenge',
    rp: { name: 'SentinelVault', id: 'localhost' },
    user: { id: 'test_user', name: 'test_user' },
    pubKeyCredParams: [],
  }),
  verifyRegistrationResponse: jest.fn().mockResolvedValue({
    verified: true,
    registrationInfo: {
      credential: {
        id: 'mock-cred-id',
        publicKey: Buffer.from('mock-pub-key'),
        counter: 0,
      },
    },
  }),
  generateAuthenticationOptions: jest.fn().mockResolvedValue({
    challenge: 'mock-auth-challenge',
    allowCredentials: [{ id: 'mock-cred-id', type: 'public-key' }],
  }),
  verifyAuthenticationResponse: jest.fn().mockResolvedValue({
    verified: true,
    authenticationInfo: {
      newCounter: 1,
    },
  }),
}));

describe('AuthService Integration Tests (SRP-6a, MFA, & Lockout)', () => {
  let app: INestApplication;
  let userRepository: UserRepository;

  const username = 'test_user';
  const password = 'super_secure_master_password_derived_key'; // represented as derived master key bytes

  // SRP-6a Client math simulator for integration tests
  async function computeClientRegister(user: string, pass: string, salt: Buffer) {
    const x = await computeClientX(user, pass, salt);
    const v = SrpServer.modPow(SrpServer.g, x, SrpServer.N);
    return {
      saltHex: salt.toString('hex'),
      verifierHex: v.toString(16),
    };
  }

  async function computeClientX(user: string, pass: string, salt: Buffer): Promise<bigint> {
    const masterKeyBytes = Buffer.from(pass, 'utf-8');
    const masterKeyHex = masterKeyBytes.toString('hex');
    const identity = Buffer.from(`${user}:${masterKeyHex}`, 'utf-8');
    const innerHash = sha256(identity);
    const outerInput = Buffer.concat([salt, innerHash]);
    const outerHash = sha256(outerInput);
    return bufferToBigInt(outerHash);
  }

  async function simulateClientLoginChallenge(user: string, pass: string, salt: Buffer, B: bigint, a: bigint, A: bigint) {
    const k = SrpServer.getMultiplierK();
    const x = await computeClientX(user, pass, salt);

    const u = SrpServer.calculateU(A, B);
    if (u === BigInt(0)) {
      throw new Error('u cannot be 0');
    }

    // S = (B - k * g^x) ^ (a + u * x) mod N
    const exp = a + u * x;
    const gx = SrpServer.modPow(SrpServer.g, x, SrpServer.N);
    const base = (B - ((k * gx) % SrpServer.N) + SrpServer.N) % SrpServer.N;
    const S = SrpServer.modPow(base, exp, SrpServer.N);

    const sBytes = bigIntToBuffer(S, 256);
    const sessionKey = sha256(sBytes);

    // M1 = H(H(N) ^ H(g), H(username), salt, A, B, sessionKey)
    const hn = sha256(bigIntToBuffer(SrpServer.N, 256));
    const hg = sha256(bigIntToBuffer(SrpServer.g, 256));
    const hXor = Buffer.alloc(32);
    for (let i = 0; i < 32; i++) {
      hXor[i] = hn[i] ^ hg[i];
    }

    const hu = sha256(Buffer.from(user, 'utf-8'));
    const aBytes = bigIntToBuffer(A, 256);
    const bBytes = bigIntToBuffer(B, 256);

    const m1Input = Buffer.concat([hXor, hu, salt, aBytes, bBytes, sessionKey]);
    const m1 = sha256(m1Input);

    // Server evidence M2 = H(A, M1, sessionKey)
    const m2Input = Buffer.concat([aBytes, m1, sessionKey]);
    const expectedM2 = sha256(m2Input);

    return {
      m1Hex: m1.toString('hex'),
      expectedM2Hex: expectedM2.toString('hex'),
    };
  }

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();

    userRepository = moduleFixture.get<UserRepository>(UserRepository);
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(async () => {
    await userRepository.clear();
  });

  it('rate limiting headers are present on auth endpoints', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/login/step1')
      .send({ username: 'invalid_user', A: '123456' });

    expect(res.headers['x-ratelimit-limit']).toBeDefined();
    expect(res.headers['x-ratelimit-remaining']).toBeDefined();
    expect(res.headers['x-ratelimit-reset']).toBeDefined();
  });

  it('register -> login successfully (SRP-6a mutual auth)', async () => {
    const saltBytes = crypto.randomBytes(16);
    const regParams = await computeClientRegister(username, password, saltBytes);

    // 1. Register User
    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username,
        salt: regParams.saltHex,
        verifier: regParams.verifierHex,
      })
      .expect(HttpStatus.CREATED);

    // 2. Initiate Login (Step 1)
    const aBytes = crypto.randomBytes(32);
    const a = bufferToBigInt(aBytes) % SrpServer.N;
    const A = SrpServer.modPow(SrpServer.g, a, SrpServer.N);

    const step1Response = await request(app.getHttpServer())
      .post('/auth/login/step1')
      .send({
        username,
        A: A.toString(16),
      })
      .expect(HttpStatus.OK);

    const { salt: rcvSaltHex, B: rcvBHex, challengeId } = step1Response.body;
    expect(rcvSaltHex).toBe(regParams.saltHex);
    expect(challengeId).toBeDefined();

    const rcvB = BigInt('0x' + rcvBHex);

    // 3. Complete Login (Step 2)
    const clientComputation = await simulateClientLoginChallenge(
      username,
      password,
      Buffer.from(rcvSaltHex, 'hex'),
      rcvB,
      a,
      A,
    );

    const step2Response = await request(app.getHttpServer())
      .post('/auth/login/step2')
      .send({
        challengeId,
        M1: clientComputation.m1Hex,
      })
      .expect(HttpStatus.OK);

    const { serverEvidence, token } = step2Response.body;
    expect(serverEvidence).toBe(clientComputation.expectedM2Hex);
    expect(token).toBeDefined();
  });

  it('TOTP MFA flow: setup -> enable -> mfa login verification', async () => {
    const saltBytes = crypto.randomBytes(16);
    const regParams = await computeClientRegister(username, password, saltBytes);

    // 1. Register User
    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username,
        salt: regParams.saltHex,
        verifier: regParams.verifierHex,
      })
      .expect(HttpStatus.CREATED);

    // 2. Generate TOTP secret
    const genRes = await request(app.getHttpServer())
      .post('/auth/mfa/totp/generate')
      .send({ username })
      .expect(HttpStatus.OK);

    expect(genRes.body.secret).toBeDefined();
    expect(genRes.body.provisioningUri).toBeDefined();

    const secret = genRes.body.secret;

    // Use dynamic generation helper to compute valid current code
    const helper = require('../src/auth/totp').TotpHelper;
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    let cleanSecret = secret.toUpperCase().replace(/=+$/, '');
    let bytes = [];
    let valBuffer = 0;
    let bitCount = 0;
    for (let i = 0; i < cleanSecret.length; i++) {
      const idx = alphabet.indexOf(cleanSecret[i]);
      valBuffer = (valBuffer << 5) | idx;
      bitCount += 5;
      if (bitCount >= 8) {
        bytes.push((valBuffer >> (bitCount - 8)) & 0xff);
        bitCount -= 8;
      }
    }
    const key = Buffer.from(bytes);
    const buffer = Buffer.alloc(8);
    const step = BigInt(Math.floor(Date.now() / 1000 / 30));
    let temp = step;
    for (let i = 7; i >= 0; i--) {
      buffer[i] = Number(temp & 0xffn);
      temp >>= 8n;
    }
    const hmac = crypto.createHmac('sha1', key).update(buffer).digest();
    const offset = hmac[hmac.length - 1] & 0xf;
    const binary = ((hmac[offset] & 0x7f) << 24) |
      ((hmac[offset + 1] & 0xff) << 16) |
      ((hmac[offset + 2] & 0xff) << 8) |
      (hmac[offset + 3] & 0xff);
    const currentCode = (binary % 1000000).toString().padStart(6, '0');

    // 3. Enable TOTP
    await request(app.getHttpServer())
      .post('/auth/mfa/totp/enable')
      .send({ username, code: currentCode })
      .expect(HttpStatus.OK);

    // 4. Initiate login challenge
    const aBytes = crypto.randomBytes(32);
    const a = bufferToBigInt(aBytes) % SrpServer.N;
    const A = SrpServer.modPow(SrpServer.g, a, SrpServer.N);

    const step1Response = await request(app.getHttpServer())
      .post('/auth/login/step1')
      .send({ username, A: A.toString(16) });

    const { salt: rcvSaltHex, B: rcvBHex, challengeId } = step1Response.body;
    const rcvB = BigInt('0x' + rcvBHex);

    const clientComputation = await simulateClientLoginChallenge(
      username,
      password,
      Buffer.from(rcvSaltHex, 'hex'),
      rcvB,
      a,
      A,
    );

    // 5. Login Step 2 -> Expect MFA Required response
    const step2Response = await request(app.getHttpServer())
      .post('/auth/login/step2')
      .send({ challengeId, M1: clientComputation.m1Hex })
      .expect(HttpStatus.OK);

    expect(step2Response.body.mfaRequired).toBe(true);
    expect(step2Response.body.mfaToken).toBeDefined();
    expect(step2Response.body.allowedMethods).toContain('totp');

    const mfaToken = step2Response.body.mfaToken;

    // 6. Verify TOTP to get final token
    const verifyRes = await request(app.getHttpServer())
      .post('/auth/mfa/totp/verify')
      .send({ mfaToken, code: currentCode })
      .expect(HttpStatus.OK);

    expect(verifyRes.body.token).toBeDefined();
  });

  it('WebAuthn MFA flow: register -> login flow', async () => {
    const saltBytes = crypto.randomBytes(16);
    const regParams = await computeClientRegister(username, password, saltBytes);

    // 1. Register
    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username,
        salt: regParams.saltHex,
        verifier: regParams.verifierHex,
      })
      .expect(HttpStatus.CREATED);

    // 2. Options for registration
    const optRes = await request(app.getHttpServer())
      .post('/auth/mfa/webauthn/register/options')
      .send({ username })
      .expect(HttpStatus.OK);

    expect(optRes.body.challenge).toBeDefined();

    // 3. Verify registration
    await request(app.getHttpServer())
      .post('/auth/mfa/webauthn/register/verify')
      .send({
        username,
        response: {
          id: 'mock-cred-id',
          rawId: 'mock-cred-id',
          type: 'public-key',
          response: {},
        },
      })
      .expect(HttpStatus.OK);

    // 4. Initiate login and get mfaToken
    const aBytes = crypto.randomBytes(32);
    const a = bufferToBigInt(aBytes) % SrpServer.N;
    const A = SrpServer.modPow(SrpServer.g, a, SrpServer.N);

    const step1Response = await request(app.getHttpServer())
      .post('/auth/login/step1')
      .send({ username, A: A.toString(16) });

    const { salt: rcvSaltHex, B: rcvBHex, challengeId } = step1Response.body;
    const rcvB = BigInt('0x' + rcvBHex);

    const clientComputation = await simulateClientLoginChallenge(
      username,
      password,
      Buffer.from(rcvSaltHex, 'hex'),
      rcvB,
      a,
      A,
    );

    const step2Response = await request(app.getHttpServer())
      .post('/auth/login/step2')
      .send({ challengeId, M1: clientComputation.m1Hex });

    const mfaToken = step2Response.body.mfaToken;
    expect(step2Response.body.allowedMethods).toContain('webauthn');

    // 5. Get options for WebAuthn assertion
    const authOptRes = await request(app.getHttpServer())
      .post('/auth/mfa/webauthn/login/options')
      .send({ mfaToken })
      .expect(HttpStatus.OK);

    expect(authOptRes.body.challenge).toBeDefined();

    // 6. Verify WebAuthn assertion to get final token
    const verifyRes = await request(app.getHttpServer())
      .post('/auth/mfa/webauthn/login/verify')
      .send({
        mfaToken,
        response: {
          id: 'mock-cred-id',
          rawId: 'mock-cred-id',
          type: 'public-key',
          response: {},
        },
      })
      .expect(HttpStatus.OK);

    expect(verifyRes.body.token).toBeDefined();
  });

  it('login with wrong password rejected', async () => {
    const saltBytes = crypto.randomBytes(16);
    const regParams = await computeClientRegister(username, password, saltBytes);

    // Register User
    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username,
        salt: regParams.saltHex,
        verifier: regParams.verifierHex,
      })
      .expect(HttpStatus.CREATED);

    // Initiate Login (Step 1)
    const aBytes = crypto.randomBytes(32);
    const a = bufferToBigInt(aBytes) % SrpServer.N;
    const A = SrpServer.modPow(SrpServer.g, a, SrpServer.N);

    const step1Response = await request(app.getHttpServer())
      .post('/auth/login/step1')
      .send({
        username,
        A: A.toString(16),
      })
      .expect(HttpStatus.OK);

    const { salt: rcvSaltHex, B: rcvBHex, challengeId } = step1Response.body;
    const rcvB = BigInt('0x' + rcvBHex);

    // Compute client evidence using WRONG password
    const clientComputation = await simulateClientLoginChallenge(
      username,
      'incorrect_master_password',
      Buffer.from(rcvSaltHex, 'hex'),
      rcvB,
      a,
      A,
    );

    // Complete Login (Step 2) -> Expect UNAUTHORIZED
    await request(app.getHttpServer())
      .post('/auth/login/step2')
      .send({
        challengeId,
        M1: clientComputation.m1Hex,
      })
      .expect(HttpStatus.UNAUTHORIZED);
  });

  it('account lockout after 5 failed attempts', async () => {
    const saltBytes = crypto.randomBytes(16);
    const regParams = await computeClientRegister(username, password, saltBytes);

    // Register User
    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username,
        salt: regParams.saltHex,
        verifier: regParams.verifierHex,
      })
      .expect(HttpStatus.CREATED);

    // Perform 5 failed attempts
    for (let i = 0; i < 5; i++) {
      const aBytes = crypto.randomBytes(32);
      const a = bufferToBigInt(aBytes) % SrpServer.N;
      const A = SrpServer.modPow(SrpServer.g, a, SrpServer.N);

      const step1Response = await request(app.getHttpServer())
        .post('/auth/login/step1')
        .send({
          username,
          A: A.toString(16),
        })
        .expect(HttpStatus.OK);

      const { salt: rcvSaltHex, B: rcvBHex, challengeId } = step1Response.body;
      const rcvB = BigInt('0x' + rcvBHex);

      const clientComputation = await simulateClientLoginChallenge(
        username,
        'incorrect_master_password',
        Buffer.from(rcvSaltHex, 'hex'),
        rcvB,
        a,
        A,
      );

      await request(app.getHttpServer())
        .post('/auth/login/step2')
        .send({
          challengeId,
          M1: clientComputation.m1Hex,
        })
        .expect(HttpStatus.UNAUTHORIZED);
    }

    // 6th attempt (even with correct parameters) should fail at Step 1 with HttpStatus.LOCKED (423)
    const aBytes = crypto.randomBytes(32);
    const a = bufferToBigInt(aBytes) % SrpServer.N;
    const A = SrpServer.modPow(SrpServer.g, a, SrpServer.N);

    await request(app.getHttpServer())
      .post('/auth/login/step1')
      .send({
        username,
        A: A.toString(16),
      })
      .expect(423);
  });

  describe('Primary Passkey Authentication Tests', () => {
    it('register passkey -> primary login options -> verify login successfully', async () => {
      const saltBytes = crypto.randomBytes(16);
      const regParams = await computeClientRegister(username, password, saltBytes);

      // 1. Register User (OPAQUE)
      await request(app.getHttpServer())
        .post('/auth/register')
        .send({
          username,
          salt: regParams.saltHex,
          verifier: regParams.verifierHex,
        })
        .expect(HttpStatus.CREATED);

      // 2. Generate passkey registration options
      const regOptRes = await request(app.getHttpServer())
        .post('/auth/passkey/register/options')
        .send({ username })
        .expect(HttpStatus.OK);

      expect(regOptRes.body.challenge).toBe('mock-reg-challenge');

      // 3. Verify passkey registration
      await request(app.getHttpServer())
        .post('/auth/passkey/register/verify')
        .send({
          username,
          response: {
            id: 'mock-cred-id',
            rawId: 'mock-cred-id',
            type: 'public-key',
            response: {},
          },
        })
        .expect(HttpStatus.OK);

      // 4. Generate passkey login options (username-based)
      const loginOptRes = await request(app.getHttpServer())
        .post('/auth/passkey/login/options')
        .send({ username })
        .expect(HttpStatus.OK);

      expect(loginOptRes.body.challenge).toBe('mock-auth-challenge');
      expect(loginOptRes.body.allowCredentials[0].id).toBe('mock-cred-id');

      // 5. Verify passkey login
      const verifyRes = await request(app.getHttpServer())
        .post('/auth/passkey/login/verify')
        .send({
          challenge: 'mock-auth-challenge',
          response: {
            id: 'mock-cred-id',
            rawId: 'mock-cred-id',
            type: 'public-key',
            response: {},
          },
        })
        .expect(HttpStatus.OK);

      expect(verifyRes.body.token).toBeDefined();
    });

    it('rejects primary passkey login when assertion is invalid/tampered', async () => {
      const saltBytes = crypto.randomBytes(16);
      const regParams = await computeClientRegister(username, password, saltBytes);

      // 1. Register User (OPAQUE)
      await request(app.getHttpServer())
        .post('/auth/register')
        .send({
          username,
          salt: regParams.saltHex,
          verifier: regParams.verifierHex,
        })
        .expect(HttpStatus.CREATED);

      // 2. Register Passkey
      await request(app.getHttpServer())
        .post('/auth/passkey/register/options')
        .send({ username })
        .expect(HttpStatus.OK);

      await request(app.getHttpServer())
        .post('/auth/passkey/register/verify')
        .send({
          username,
          response: {
            id: 'mock-cred-id',
            rawId: 'mock-cred-id',
            type: 'public-key',
            response: {},
          },
        })
        .expect(HttpStatus.OK);

      // 3. Generate passkey login options
      await request(app.getHttpServer())
        .post('/auth/passkey/login/options')
        .send({ username })
        .expect(HttpStatus.OK);

      // 4. Mock verifyAuthenticationResponse to fail/reject
      const simpleWebAuthn = require('@simplewebauthn/server');
      const originalVerify = simpleWebAuthn.verifyAuthenticationResponse;
      simpleWebAuthn.verifyAuthenticationResponse = jest.fn().mockResolvedValue({
        verified: false,
      });

      try {
        // 5. Verify passkey login -> Expect UNAUTHORIZED
        await request(app.getHttpServer())
          .post('/auth/passkey/login/verify')
          .send({
            challenge: 'mock-auth-challenge',
            response: {
              id: 'mock-cred-id',
              rawId: 'mock-cred-id',
              type: 'public-key',
              response: {},
            },
          })
          .expect(HttpStatus.UNAUTHORIZED);
      } finally {
        // Restore original mock
        simpleWebAuthn.verifyAuthenticationResponse = originalVerify;
      }
    });

    it('usernameless passkey login options and verification works', async () => {
      const saltBytes = crypto.randomBytes(16);
      const regParams = await computeClientRegister(username, password, saltBytes);

      // 1. Register User (OPAQUE)
      await request(app.getHttpServer())
        .post('/auth/register')
        .send({
          username,
          salt: regParams.saltHex,
          verifier: regParams.verifierHex,
        })
        .expect(HttpStatus.CREATED);

      // 2. Register Passkey
      await request(app.getHttpServer())
        .post('/auth/passkey/register/options')
        .send({ username })
        .expect(HttpStatus.OK);

      await request(app.getHttpServer())
        .post('/auth/passkey/register/verify')
        .send({
          username,
          response: {
            id: 'mock-cred-id',
            rawId: 'mock-cred-id',
            type: 'public-key',
            response: {},
          },
        })
        .expect(HttpStatus.OK);

      // 3. Generate login options WITHOUT username (usernameless)
      const simpleWebAuthn = require('@simplewebauthn/server');
      const originalAuthOptions = simpleWebAuthn.generateAuthenticationOptions;
      simpleWebAuthn.generateAuthenticationOptions = jest.fn().mockResolvedValue({
        challenge: 'mock-auth-challenge',
        allowCredentials: undefined,
      });

      try {
        const optionsRes = await request(app.getHttpServer())
          .post('/auth/passkey/login/options')
          .send({})
          .expect(HttpStatus.OK);

        expect(optionsRes.body.allowCredentials).toBeUndefined();
      } finally {
        simpleWebAuthn.generateAuthenticationOptions = originalAuthOptions;
      }

      // 4. Verify login with credential id lookup
      const verifyRes = await request(app.getHttpServer())
        .post('/auth/passkey/login/verify')
        .send({
          challenge: 'mock-auth-challenge',
          response: {
            id: 'mock-cred-id',
            rawId: 'mock-cred-id',
            type: 'public-key',
            response: {},
          },
        })
        .expect(HttpStatus.OK);

      expect(verifyRes.body.token).toBeDefined();
    });
  });
});
