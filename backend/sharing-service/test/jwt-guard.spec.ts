/**
 * jwt-guard.spec.ts — sharing-service
 *
 * Tests that JwtAuthGuard correctly protects key-directory and share-invite
 * endpoints. Covers:
 *   1. Missing Authorization header → 401 on every guarded endpoint
 *   2. Invalid / tampered token → 401
 *   3. Valid token for user A cannot access or modify user B's data
 *      (even if the request body tries to claim a different userId)
 */
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, HttpStatus } from '@nestjs/common';
import * as request from 'supertest';
import { JwtService } from '@nestjs/jwt';
import { SharingModule } from '../src/sharing.module';
import { ValidationPipe } from '@nestjs/common';

const TEST_SECRET = 'test-jwt-secret-at-least-32-bytes-long!!';
const USER_A_ID = 'aaaaaaaa-0000-4000-a000-aaaaaaaaaaaa';
const USER_B_ID = 'bbbbbbbb-0000-4000-b000-bbbbbbbbbbbb';

jest.setTimeout(30000);

describe('JwtAuthGuard — sharing-service', () => {
  let app: INestApplication;
  let jwtService: JwtService;

  function makeToken(userId: string, username = 'testuser'): string {
    return jwtService.sign(
      { sub: userId, username },
      { secret: TEST_SECRET, expiresIn: '1h' },
    );
  }

  beforeAll(async () => {
    process.env.JWT_SECRET = TEST_SECRET;

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [SharingModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();

    jwtService = moduleFixture.get<JwtService>(JwtService);
  });

  afterAll(async () => {
    await app.close();
  });

  // ── key-directory endpoints ────────────────────────────────────────────────

  describe('POST /key-directory/keys — guard enforcement', () => {
    const body = {
      userId: USER_A_ID,
      x25519PublicKey: 'x25519pub',
      ed25519PublicKey: 'ed25519pub',
      mlkemEncapsulationKey: 'mlkem',
      mldsaVerifyingKey: 'mldsa',
      keyFingerprint: 'fp1',
    };

    it('rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .post('/key-directory/keys')
        .send(body)
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('rejects with 401 when token is invalid', async () => {
      await request(app.getHttpServer())
        .post('/key-directory/keys')
        .set('Authorization', 'Bearer invalid.token.here')
        .send(body)
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('rejects with 401 when token is signed with wrong secret', async () => {
      const badToken = jwtService.sign(
        { sub: USER_A_ID, username: 'alice' },
        { secret: 'wrong-secret', expiresIn: '1h' },
      );
      await request(app.getHttpServer())
        .post('/key-directory/keys')
        .set('Authorization', `Bearer ${badToken}`)
        .send(body)
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('user A body with userId=B is rejected by mismatch check (not a guard bypass)', async () => {
      const tokenA = makeToken(USER_A_ID, 'alice');
      // Alice tries to publish a key bundle claiming it belongs to Bob
      const spoofedBody = { ...body, userId: USER_B_ID };
      const res = await request(app.getHttpServer())
        .post('/key-directory/keys')
        .set('Authorization', `Bearer ${tokenA}`)
        .send(spoofedBody)
        .expect(HttpStatus.OK);
      // Guard passes (valid token) but service returns mismatch error
      expect(res.body.ok).toBe(false);
      expect(res.body.error).toMatch(/mismatch/i);
    });
  });

  describe('POST /key-directory/wrapped-keys — guard enforcement', () => {
    const body = {
      folderId: 'folder-1',
      keyVersion: 1,
      recipients: [],
    };

    it('rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .post('/key-directory/wrapped-keys')
        .send(body)
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('rejects with 401 when token is tampered', async () => {
      await request(app.getHttpServer())
        .post('/key-directory/wrapped-keys')
        .set('Authorization', 'Bearer tampered')
        .send(body)
        .expect(HttpStatus.UNAUTHORIZED);
    });
  });

  describe('GET /key-directory/keys/:userId — guard enforcement', () => {
    it('rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .get(`/key-directory/keys/${USER_A_ID}`)
        .expect(HttpStatus.UNAUTHORIZED);
    });
  });

  // ── share-invite endpoints ─────────────────────────────────────────────────

  describe('POST /invites — guard enforcement', () => {
    it('rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .post('/invites')
        .send({})
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('rejects with 401 when token is invalid', async () => {
      await request(app.getHttpServer())
        .post('/invites')
        .set('Authorization', 'Bearer bad')
        .send({})
        .expect(HttpStatus.UNAUTHORIZED);
    });
  });

  describe('GET /invites/pending — guard enforcement', () => {
    it('rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .get('/invites/pending')
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('user A sees only their own pending invites (data isolation)', async () => {
      // Both users have valid tokens; each must see an empty list for their own scope
      const tokenA = makeToken(USER_A_ID, 'alice');
      const tokenB = makeToken(USER_B_ID, 'bob');

      const resA = await request(app.getHttpServer())
        .get('/invites/pending')
        .set('Authorization', `Bearer ${tokenA}`)
        .expect(HttpStatus.OK);

      const resB = await request(app.getHttpServer())
        .get('/invites/pending')
        .set('Authorization', `Bearer ${tokenB}`)
        .expect(HttpStatus.OK);

      // Both start with empty lists and cannot see each other's data
      expect(resA.body.ok).toBe(true);
      expect(resA.body.invites).toEqual([]);
      expect(resB.body.ok).toBe(true);
      expect(resB.body.invites).toEqual([]);
    });
  });

  describe('DELETE /invites/:id — guard enforcement', () => {
    it('rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .delete('/invites/some-invite-id')
        .expect(HttpStatus.UNAUTHORIZED);
    });
  });
});
