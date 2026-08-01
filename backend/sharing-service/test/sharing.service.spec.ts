import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { KeyDirectoryService } from '../src/key-directory/key-directory.service';
import { KeyBundle } from '../src/key-directory/entities/key-bundle.entity';
import { WrappedKeyVersion } from '../src/key-directory/entities/wrapped-key-version.entity';
import { WrappedKeyRecipient } from '../src/key-directory/entities/wrapped-key-recipient.entity';
import { ShareInviteService } from '../src/share-invite/share-invite.service';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeBundle(userId: string) {
  return {
    userId,
    x25519PublicKey: Buffer.from(`x25519-pub-${userId}`).toString('base64url'),
    ed25519PublicKey: Buffer.from(`ed25519-pub-${userId}`).toString('base64url'),
    mlkemEncapsulationKey: Buffer.from(`mlkem-ek-${userId}`).toString('base64url'),
    mldsaVerifyingKey: Buffer.from(`mldsa-vk-${userId}`).toString('base64url'),
    keyFingerprint: `fp-${userId}`,
  };
}

const FOLDER_ID  = '00000000-0000-0000-0000-000000000001';
const ALICE_ID   = '00000000-0000-0000-0000-000000000002';
const BOB_ID     = '00000000-0000-0000-0000-000000000003';
const CHARLIE_ID = '00000000-0000-0000-0000-000000000004';

function makeWrappedKey(recipientUserId: string) {
  return {
    recipientUserId,
    ephemeralX25519PublicKey: 'ephem-pub',
    mlkemCiphertext: 'mlkem-ct',
    aesNonce: 'nonce-12',
    wrappedFolderKey: 'wrapped-fk-ciphertext',
  };
}

// ── Key Directory Tests ───────────────────────────────────────────────────────
//
// Because KeyDirectoryService now uses TypeORM repositories we inject in-memory
// Maps as mock repositories so the tests remain fast and database-free.

/** Minimal mock repository backed by a JS array; no jest.fn() contamination. */
function makeRepo<T extends object>(pkFields: (keyof T)[]) {
  const rows: T[] = [];

  const pkKey = (row: Partial<T>) =>
    pkFields.map((f) => (row[f] !== undefined ? String(row[f]) : '')).join('|');

  const matchesWhere = (row: T, where: Partial<T>): boolean =>
    Object.entries(where as Record<string, unknown>).every(
      ([k, v]) => (row as Record<string, unknown>)[k] === v,
    );

  return {
    _rows: rows,
    create: (dto: Partial<T>) => ({ ...dto }) as T,
    save: async (entityOrArray: T | T[]): Promise<T | T[]> => {
      const items = Array.isArray(entityOrArray) ? entityOrArray : [entityOrArray];
      for (const item of items) {
        const key = pkKey(item);
        const idx = rows.findIndex((r) => pkKey(r) === key);
        if (idx >= 0) {
          rows[idx] = item;
        } else {
          rows.push(item);
        }
      }
      return Array.isArray(entityOrArray) ? items : items[0];
    },
    findOne: async ({ where }: { where: Partial<T> }): Promise<T | null> => {
      return rows.find((r) => matchesWhere(r, where)) ?? null;
    },
    find: async ({ where }: { where?: Partial<T> } = {}): Promise<T[]> => {
      if (!where) return [...rows];
      return rows.filter((r) => matchesWhere(r, where));
    },
    count: async ({ where }: { where?: Partial<T> } = {}): Promise<number> => {
      if (!where) return rows.length;
      return rows.filter((r) => matchesWhere(r, where)).length;
    },
    delete: async ({ where }: { where?: Partial<T> }): Promise<{ affected: number }> => {
      const before = rows.length;
      if (where) {
        const toDelete = rows.filter((r) => matchesWhere(r, where));
        toDelete.forEach((d) => rows.splice(rows.indexOf(d), 1));
      }
      return { affected: before - rows.length };
    },
    // Lightweight QueryBuilder stub used by getCurrentKeyVersion
    createQueryBuilder: () => {
      let _params: Record<string, unknown> = {};
      let _order: [string, 'ASC' | 'DESC'] | null = null;
      let _limit: number | null = null;

      const qb = {
        where: (_cond: string, params?: Record<string, unknown>) => {
          _params = params ?? {};
          return qb;
        },
        orderBy: (col: string, dir: 'ASC' | 'DESC') => {
          _order = [col, dir];
          return qb;
        },
        limit: (n: number) => {
          _limit = n;
          return qb;
        },
        getOne: async (): Promise<T | null> => {
          let filtered = rows.filter((r) =>
            Object.entries(_params).every(
              ([k, v]) => (r as Record<string, unknown>)[k] === v,
            ),
          );
          if (_order) {
            // Strip table alias prefix (e.g. 'v.keyVersion' → 'keyVersion')
            const col = _order[0].includes('.') ? _order[0].split('.')[1] : _order[0];
            const dir = _order[1];
            filtered = [...filtered].sort((a, b) => {
              const av = String((a as Record<string, unknown>)[col]);
              const bv = String((b as Record<string, unknown>)[col]);
              return dir === 'ASC' ? av.localeCompare(bv) : bv.localeCompare(av);
            });
          }
          if (_limit) filtered = filtered.slice(0, _limit);
          return filtered[0] ?? null;
        },
      };
      return qb;
    },
  };
}

describe('KeyDirectoryService', () => {
  let svc: KeyDirectoryService;
  let keyBundleRepo: ReturnType<typeof makeRepo<KeyBundle>>;
  let versionRepo: ReturnType<typeof makeRepo<WrappedKeyVersion>>;
  let recipientRepo: ReturnType<typeof makeRepo<WrappedKeyRecipient>>;

  beforeEach(async () => {
    keyBundleRepo  = makeRepo<KeyBundle>(['userId']);
    versionRepo    = makeRepo<WrappedKeyVersion>(['folderId', 'keyVersion']);
    recipientRepo  = makeRepo<WrappedKeyRecipient>(['recipientUserId', 'folderId', 'keyVersion']);

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        KeyDirectoryService,
        { provide: getRepositoryToken(KeyBundle), useValue: keyBundleRepo },
        { provide: getRepositoryToken(WrappedKeyVersion), useValue: versionRepo },
        { provide: getRepositoryToken(WrappedKeyRecipient), useValue: recipientRepo },
      ],
    }).compile();

    svc = module.get<KeyDirectoryService>(KeyDirectoryService);
  });

  it('publishes a key bundle and retrieves it', async () => {
    await svc.publishKeyBundle(makeBundle(ALICE_ID));
    const b = await svc.getKeyBundle(ALICE_ID);
    expect(b.userId).toBe(ALICE_ID);
    expect(b.keyFingerprint).toBe(`fp-${ALICE_ID}`);
  });

  it('throws NotFoundException for unknown user', async () => {
    await expect(svc.getKeyBundle('unknown-id')).rejects.toThrow(NotFoundException);
  });

  it('publishes wrapped keys and fetches own record', async () => {
    await svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    const rec = await svc.fetchWrappedKey(BOB_ID, { folderId: FOLDER_ID });
    expect(rec.recipientUserId).toBe(BOB_ID);
  });

  it("prevents fetching another user's wrapped key", async () => {
    await svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    await expect(
      svc.fetchWrappedKey(CHARLIE_ID, { folderId: FOLDER_ID }),
    ).rejects.toThrow(NotFoundException);
  });

  it('enforces monotonic key versioning', async () => {
    await svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v2',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    await expect(
      svc.publishWrappedKeys(ALICE_ID, {
        folderId: FOLDER_ID,
        keyVersion: 'v1', // older version — must be rejected
        recipients: [makeWrappedKey(BOB_ID)],
      }),
    ).rejects.toThrow(ConflictException);
  });

  it('revokes recipient and prevents re-inclusion', async () => {
    await svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID), makeWrappedKey(CHARLIE_ID)],
    });

    // Revoke Bob — only Charlie gets the new wrapped key
    await svc.revokeRecipient(ALICE_ID, {
      folderId: FOLDER_ID,
      recipientUserId: BOB_ID,
      newKeyVersion: 'v2',
      remainingRecipients: [makeWrappedKey(CHARLIE_ID)],
    });

    // Charlie can still access v2 (latest)
    const rec = await svc.fetchWrappedKey(CHARLIE_ID, { folderId: FOLDER_ID });
    expect(rec.recipientUserId).toBe(CHARLIE_ID);

    // Bob cannot access v2
    await expect(
      svc.fetchWrappedKey(BOB_ID, { folderId: FOLDER_ID }),
    ).rejects.toThrow(NotFoundException);
  });

  it('rejects revocation that includes the revoked user', async () => {
    await svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    await expect(
      svc.revokeRecipient(ALICE_ID, {
        folderId: FOLDER_ID,
        recipientUserId: BOB_ID,
        newKeyVersion: 'v2',
        remainingRecipients: [makeWrappedKey(BOB_ID)], // revoked user in remaining — must fail
      }),
    ).rejects.toThrow(BadRequestException);
  });
});

// ── Share Invite Tests ────────────────────────────────────────────────────────

describe('ShareInviteService', () => {
  let svc: ShareInviteService;

  const INVITE_PAYLOAD = {
    folderId: FOLDER_ID,
    recipientUserId: BOB_ID,
    signedPayload: 'payload-b64',
    ed25519Signature: 'ed-sig-b64',
    mldsaSignature: 'mldsa-sig-b64',
    wrappedFolderKeyPayload: 'wrapped-b64',
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [ShareInviteService],
    }).compile();
    svc = module.get<ShareInviteService>(ShareInviteService);
  });

  it('creates an invite and lists it for recipient', () => {
    svc.createInvite(ALICE_ID, INVITE_PAYLOAD);
    const pending = svc.listPendingForRecipient(BOB_ID);
    expect(pending).toHaveLength(1);
    expect(pending[0]?.folderId).toBe(FOLDER_ID);
  });

  it('prevents duplicate pending invites for same folder+recipient', () => {
    svc.createInvite(ALICE_ID, INVITE_PAYLOAD);
    expect(() => svc.createInvite(ALICE_ID, INVITE_PAYLOAD)).toThrow(ConflictException);
  });

  it('accepts invite only when fingerprintConfirmed=true', () => {
    const inv = svc.createInvite(ALICE_ID, INVITE_PAYLOAD);
    const accepted = svc.acceptInvite(BOB_ID, {
      inviteId: inv.inviteId,
      fingerprintConfirmed: 'true',
    });
    expect(accepted.status).toBe('accepted');
    expect(accepted.fingerprintVerified).toBe(true);
  });

  it('rejects acceptance without fingerprint confirmation', () => {
    const inv = svc.createInvite(ALICE_ID, INVITE_PAYLOAD);
    expect(() =>
      svc.acceptInvite(BOB_ID, {
        inviteId: inv.inviteId,
        fingerprintConfirmed: 'false' as 'true',
      }),
    ).toThrow(BadRequestException);
  });

  it('provides wrapped key payload only after accepted+fingerprint-verified', () => {
    const inv = svc.createInvite(ALICE_ID, INVITE_PAYLOAD);

    // Before acceptance — must fail
    expect(() => svc.getAcceptedInvitePayload(BOB_ID, inv.inviteId))
      .toThrow(BadRequestException);

    // After acceptance with fingerprint confirmation — must succeed
    svc.acceptInvite(BOB_ID, { inviteId: inv.inviteId, fingerprintConfirmed: 'true' });
    const payload = svc.getAcceptedInvitePayload(BOB_ID, inv.inviteId);
    expect(payload.wrappedFolderKeyPayload).toBe('wrapped-b64');
  });

  it('decline removes invite from pending list', () => {
    const inv = svc.createInvite(ALICE_ID, INVITE_PAYLOAD);
    svc.declineInvite(BOB_ID, { inviteId: inv.inviteId });
    expect(svc.listPendingForRecipient(BOB_ID)).toHaveLength(0);
  });
});
