import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, HttpStatus } from '@nestjs/common';
import * as request from 'supertest';
import { JwtService } from '@nestjs/jwt';
import { AppModule } from '../src/app.module';
import { SyncService } from '../src/sync/sync.service';

jest.setTimeout(30000);

const TEST_SECRET = 'test-jwt-secret-at-least-32-bytes-long!!';
const USER_A_ID = '00000000-0000-0000-0000-000000000001';
const USER_B_ID = '00000000-0000-0000-0000-000000000002';

describe('SyncService Integration Tests (Version Conflicts & Pull/Push)', () => {
  let app: INestApplication;
  let syncService: SyncService;
  let jwtService: JwtService;

  /** Mint a valid test JWT for the given userId. */
  function makeToken(userId: string, username = 'testuser'): string {
    return jwtService.sign(
      { sub: userId, username },
      { secret: TEST_SECRET, expiresIn: '1h' },
    );
  }

  const item1 = {
    id: '00000000-0000-0000-0000-000000000010',
    encryptedBlob: 'base64ciphertext1',
    nonce: 'nonce1',
    version: 1,
    updatedAt: new Date().toISOString(),
    isDeleted: false,
  };

  beforeAll(async () => {
    process.env.JWT_SECRET = TEST_SECRET;

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();

    syncService = moduleFixture.get<SyncService>(SyncService);
    jwtService = moduleFixture.get<JwtService>(JwtService);
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(async () => {
    await syncService.clear();
  });

  // ── JwtAuthGuard enforcement tests ────────────────────────────────────────

  describe('JwtAuthGuard — guard-level rejection tests', () => {
    it('GET /sync/pull — rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .get('/sync/pull')
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('GET /sync/pull — rejects with 401 when token is malformed (not a JWT)', async () => {
      await request(app.getHttpServer())
        .get('/sync/pull')
        .set('Authorization', 'Bearer not.a.valid.jwt')
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('GET /sync/pull — rejects with 401 when token is signed with wrong secret', async () => {
      const tamperedToken = jwtService.sign(
        { sub: USER_A_ID, username: 'alice' },
        { secret: 'wrong-secret', expiresIn: '1h' },
      );
      await request(app.getHttpServer())
        .get('/sync/pull')
        .set('Authorization', `Bearer ${tamperedToken}`)
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('POST /sync/push — rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .post('/sync/push')
        .send([item1])
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('POST /sync/vault-key — rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .post('/sync/vault-key')
        .send({ salt: 'abc', wrappedKey: 'def' })
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('GET /sync/vault-key — rejects with 401 when Authorization header is missing', async () => {
      await request(app.getHttpServer())
        .get('/sync/vault-key')
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('User A token cannot read User B data (data isolation)', async () => {
      const tokenA = makeToken(USER_A_ID, 'alice');
      const tokenB = makeToken(USER_B_ID, 'bob');

      // Bob pushes an item
      await request(app.getHttpServer())
        .post('/sync/push')
        .set('Authorization', `Bearer ${tokenB}`)
        .send([item1])
        .expect(HttpStatus.OK);

      // Alice pulls — she must get an empty array, not Bob's item
      const res = await request(app.getHttpServer())
        .get('/sync/pull')
        .set('Authorization', `Bearer ${tokenA}`)
        .expect(HttpStatus.OK);

      expect(res.body).toEqual([]);
    });

    it('User A token cannot overwrite User B vault-key', async () => {
      const tokenA = makeToken(USER_A_ID, 'alice');
      const tokenB = makeToken(USER_B_ID, 'bob');

      // Bob saves a vault key
      await request(app.getHttpServer())
        .post('/sync/vault-key')
        .set('Authorization', `Bearer ${tokenB}`)
        .send({ salt: 'bob-salt', wrappedKey: 'bob-key' })
        .expect(HttpStatus.OK);

      // Alice saves her own vault key
      await request(app.getHttpServer())
        .post('/sync/vault-key')
        .set('Authorization', `Bearer ${tokenA}`)
        .send({ salt: 'alice-salt', wrappedKey: 'alice-key' })
        .expect(HttpStatus.OK);

      // Bob retrieves his vault key — must still be his original
      const bobRes = await request(app.getHttpServer())
        .get('/sync/vault-key')
        .set('Authorization', `Bearer ${tokenB}`)
        .expect(HttpStatus.OK);

      expect(bobRes.body.salt).toBe('bob-salt');
      expect(bobRes.body.wrappedKey).toBe('bob-key');
    });
  });

  // ── Functional tests (previously x-user-id, now Bearer token) ────────────

  it('GET /sync/pull - returns empty array for new user', async () => {
    const token = makeToken(USER_A_ID);
    const res = await request(app.getHttpServer())
      .get('/sync/pull')
      .set('Authorization', `Bearer ${token}`)
      .expect(HttpStatus.OK);

    expect(res.body).toEqual([]);
  });

  it('POST /sync/push - pushes new items successfully', async () => {
    const token = makeToken(USER_A_ID);

    const res = await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([item1])
      .expect(HttpStatus.OK);

    expect(res.body).toEqual({ success: true });

    const pulled = await request(app.getHttpServer())
      .get('/sync/pull')
      .set('Authorization', `Bearer ${token}`)
      .expect(HttpStatus.OK);

    expect(pulled.body.length).toBe(1);
    expect(pulled.body[0].id).toBe(item1.id);
  });

  it('POST /sync/push - updates existing item with newer version', async () => {
    const token = makeToken(USER_A_ID);

    await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([item1])
      .expect(HttpStatus.OK);

    const itemUpdate = {
      ...item1,
      encryptedBlob: 'updatedBase64ciphertext',
      version: 2,
      updatedAt: new Date().toISOString(),
    };

    await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([itemUpdate])
      .expect(HttpStatus.OK);

    const pulled = await request(app.getHttpServer())
      .get('/sync/pull')
      .set('Authorization', `Bearer ${token}`)
      .expect(HttpStatus.OK);

    expect(pulled.body[0].version).toBe(2);
    expect(pulled.body[0].encryptedBlob).toBe('updatedBase64ciphertext');
  });

  it('POST /sync/push - handles identical duplicate push idempotently', async () => {
    const token = makeToken(USER_A_ID);

    await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([item1])
      .expect(HttpStatus.OK);

    await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([item1])
      .expect(HttpStatus.OK);
  });

  it('POST /sync/push - returns 409 Conflict when client version is outdated', async () => {
    const token = makeToken(USER_A_ID);

    await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([item1])
      .expect(HttpStatus.OK);

    const itemVersion2 = { ...item1, version: 2, encryptedBlob: 'server_version_2' };
    await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([itemVersion2])
      .expect(HttpStatus.OK);

    const staleClientPush = { ...item1, version: 1, encryptedBlob: 'stale_client_version_1' };
    const res = await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([staleClientPush])
      .expect(HttpStatus.CONFLICT);

    expect(res.body.message).toBe('Version conflict detected');
    expect(res.body.conflicts.length).toBe(1);
    expect(res.body.conflicts[0].version).toBe(2);
    expect(res.body.conflicts[0].encryptedBlob).toBe('server_version_2');
  });

  it('POST /sync/push - returns 409 Conflict when versions are equal but contents differ', async () => {
    const token = makeToken(USER_A_ID);

    await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([item1])
      .expect(HttpStatus.OK);

    const conflictPush = { ...item1, encryptedBlob: 'different_content_version_1' };
    const res = await request(app.getHttpServer())
      .post('/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send([conflictPush])
      .expect(HttpStatus.CONFLICT);

    expect(res.body.statusCode).toBe(409);
    expect(res.body.conflicts.length).toBe(1);
    expect(res.body.conflicts[0].encryptedBlob).toBe(item1.encryptedBlob);
  });

  it('POST /sync/vault-key and GET /sync/vault-key - saves and retrieves wrapped vault key and salt', async () => {
    const token = makeToken(USER_A_ID);
    const salt = 'dummysalthex';
    const wrappedKey = 'dummywrappedkeyhex';

    await request(app.getHttpServer())
      .get('/sync/vault-key')
      .set('Authorization', `Bearer ${token}`)
      .expect(HttpStatus.NOT_FOUND);

    await request(app.getHttpServer())
      .post('/sync/vault-key')
      .set('Authorization', `Bearer ${token}`)
      .send({ salt, wrappedKey })
      .expect(HttpStatus.OK);

    const res = await request(app.getHttpServer())
      .get('/sync/vault-key')
      .set('Authorization', `Bearer ${token}`)
      .expect(HttpStatus.OK);

    expect(res.body).toEqual({ salt, wrappedKey });
  });
});
