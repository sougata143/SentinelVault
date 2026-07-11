import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { KeyDirectoryService } from '../src/key-directory/key-directory.service';
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

const FOLDER_ID = '00000000-0000-0000-0000-000000000001';
const ALICE_ID  = '00000000-0000-0000-0000-000000000002';
const BOB_ID    = '00000000-0000-0000-0000-000000000003';
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

describe('KeyDirectoryService', () => {
  let svc: KeyDirectoryService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [KeyDirectoryService],
    }).compile();
    svc = module.get<KeyDirectoryService>(KeyDirectoryService);
  });

  it('publishes a key bundle and retrieves it', () => {
    svc.publishKeyBundle(makeBundle(ALICE_ID));
    const b = svc.getKeyBundle(ALICE_ID);
    expect(b.userId).toBe(ALICE_ID);
    expect(b.keyFingerprint).toBe(`fp-${ALICE_ID}`);
  });

  it('throws NotFoundException for unknown user', () => {
    expect(() => svc.getKeyBundle('unknown-id')).toThrow(NotFoundException);
  });

  it('publishes wrapped keys and fetches own record', () => {
    svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    const rec = svc.fetchWrappedKey(BOB_ID, { folderId: FOLDER_ID });
    expect(rec.recipientUserId).toBe(BOB_ID);
  });

  it('prevents fetching another user\'s wrapped key', () => {
    svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    expect(() => svc.fetchWrappedKey(CHARLIE_ID, { folderId: FOLDER_ID }))
      .toThrow(NotFoundException);
  });

  it('enforces monotonic key versioning', () => {
    svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v2',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    expect(() =>
      svc.publishWrappedKeys(ALICE_ID, {
        folderId: FOLDER_ID,
        keyVersion: 'v1', // older version — must be rejected
        recipients: [makeWrappedKey(BOB_ID)],
      }),
    ).toThrow(ConflictException);
  });

  it('revokes recipient and prevents re-inclusion', () => {
    svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID), makeWrappedKey(CHARLIE_ID)],
    });

    // Revoke Bob — only Charlie gets the new wrapped key
    svc.revokeRecipient(ALICE_ID, {
      folderId: FOLDER_ID,
      recipientUserId: BOB_ID,
      newKeyVersion: 'v2',
      remainingRecipients: [makeWrappedKey(CHARLIE_ID)],
    });

    // Charlie can still access v2
    const rec = svc.fetchWrappedKey(CHARLIE_ID, { folderId: FOLDER_ID });
    expect(rec.recipientUserId).toBe(CHARLIE_ID);

    // Bob cannot access v2
    expect(() => svc.fetchWrappedKey(BOB_ID, { folderId: FOLDER_ID }))
      .toThrow(NotFoundException);
  });

  it('rejects revocation that includes the revoked user', () => {
    svc.publishWrappedKeys(ALICE_ID, {
      folderId: FOLDER_ID,
      keyVersion: 'v1',
      recipients: [makeWrappedKey(BOB_ID)],
    });
    expect(() =>
      svc.revokeRecipient(ALICE_ID, {
        folderId: FOLDER_ID,
        recipientUserId: BOB_ID,
        newKeyVersion: 'v2',
        remainingRecipients: [makeWrappedKey(BOB_ID)], // revoked user in remaining — must fail
      }),
    ).toThrow(BadRequestException);
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
