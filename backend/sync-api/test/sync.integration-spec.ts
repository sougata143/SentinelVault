import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, HttpStatus } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { SyncService } from '../src/sync/sync.service';

describe('SyncService Integration Tests (Version Conflicts & Pull/Push)', () => {
  let app: INestApplication;
  let syncService: SyncService;

  const userId = '00000000-0000-0000-0000-000000000001';
  const item1 = {
    id: '00000000-0000-0000-0000-000000000002',
    encryptedBlob: 'base64ciphertext1',
    nonce: 'nonce1',
    version: 1,
    updatedAt: new Date().toISOString(),
    isDeleted: false,
  };

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();

    syncService = moduleFixture.get<SyncService>(SyncService);
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(async () => {
    await syncService.clear();
  });

  it('GET /sync/pull - returns empty array for new user', async () => {
    const res = await request(app.getHttpServer())
      .get('/sync/pull')
      .set('x-user-id', userId)
      .expect(HttpStatus.OK);

    expect(res.body).toEqual([]);
  });

  it('GET /sync/pull - throws bad request if x-user-id header is missing', async () => {
    await request(app.getHttpServer())
      .get('/sync/pull')
      .expect(HttpStatus.BAD_REQUEST);
  });

  it('POST /sync/push - pushes new items successfully', async () => {
    const res = await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([item1])
      .expect(HttpStatus.OK);

    expect(res.body).toEqual({ success: true });

    // Verify item is saved on server
    const pulled = await request(app.getHttpServer())
      .get('/sync/pull')
      .set('x-user-id', userId)
      .expect(HttpStatus.OK);

    expect(pulled.body.length).toBe(1);
    expect(pulled.body[0].id).toBe(item1.id);
  });

  it('POST /sync/push - updates existing item with newer version', async () => {
    // 1. Initial push
    await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([item1])
      .expect(HttpStatus.OK);

    // 2. Push update (version 2)
    const itemUpdate = {
      ...item1,
      encryptedBlob: 'updatedBase64ciphertext',
      version: 2,
      updatedAt: new Date().toISOString(),
    };

    await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([itemUpdate])
      .expect(HttpStatus.OK);

    // 3. Verify update is saved
    const pulled = await request(app.getHttpServer())
      .get('/sync/pull')
      .set('x-user-id', userId)
      .expect(HttpStatus.OK);

    expect(pulled.body[0].version).toBe(2);
    expect(pulled.body[0].encryptedBlob).toBe('updatedBase64ciphertext');
  });

  it('POST /sync/push - handles identical duplicate push idempotently', async () => {
    await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([item1])
      .expect(HttpStatus.OK);

    // Push identical item (same version, same content) -> should succeed
    await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([item1])
      .expect(HttpStatus.OK);
  });

  it('POST /sync/push - returns 409 Conflict when client version is outdated', async () => {
    // 1. Initial push (version 1)
    await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([item1])
      .expect(HttpStatus.OK);

    // 2. Push server update (version 2)
    const itemVersion2 = {
      ...item1,
      version: 2,
      encryptedBlob: 'server_version_2',
    };
    await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([itemVersion2])
      .expect(HttpStatus.OK);

    // 3. Push client stale update (still version 1)
    const staleClientPush = {
      ...item1,
      version: 1,
      encryptedBlob: 'stale_client_version_1',
    };

    const res = await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([staleClientPush])
      .expect(HttpStatus.CONFLICT);

    expect(res.body.message).toBe('Version conflict detected');
    expect(res.body.conflicts.length).toBe(1);
    expect(res.body.conflicts[0].version).toBe(2);
    expect(res.body.conflicts[0].encryptedBlob).toBe('server_version_2');
  });

  it('POST /sync/push - returns 409 Conflict when versions are equal but contents differ', async () => {
    // 1. Initial push (version 1)
    await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([item1])
      .expect(HttpStatus.OK);

    // 2. Push client push with same version (1) but different ciphertext
    const conflictPush = {
      ...item1,
      encryptedBlob: 'different_content_version_1',
    };

    const res = await request(app.getHttpServer())
      .post('/sync/push')
      .set('x-user-id', userId)
      .send([conflictPush])
      .expect(HttpStatus.CONFLICT);

    expect(res.body.statusCode).toBe(409);
    expect(res.body.conflicts.length).toBe(1);
    expect(res.body.conflicts[0].encryptedBlob).toBe(item1.encryptedBlob);
  });

  it('POST /sync/vault-key and GET /sync/vault-key - saves and retrieves wrapped vault key and salt', async () => {
    const salt = 'dummysalthex';
    const wrappedKey = 'dummywrappedkeyhex';

    // 1. Get before saving should return 404
    await request(app.getHttpServer())
      .get('/sync/vault-key')
      .set('x-user-id', userId)
      .expect(HttpStatus.NOT_FOUND);

    // 2. Save vault key
    await request(app.getHttpServer())
      .post('/sync/vault-key')
      .set('x-user-id', userId)
      .send({ salt, wrappedKey })
      .expect(HttpStatus.OK);

    // 3. Retrieve vault key and check fields
    const res = await request(app.getHttpServer())
      .get('/sync/vault-key')
      .set('x-user-id', userId)
      .expect(HttpStatus.OK);

    expect(res.body).toEqual({ salt, wrappedKey });
  });
});

