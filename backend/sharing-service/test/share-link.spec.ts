import { ShareLinkService } from '../src/share-link/share-link.service';
import { GoneException, NotFoundException, BadRequestException } from '@nestjs/common';

describe('ShareLinkService Security & Consumption Tests', () => {
  let service: ShareLinkService;

  beforeEach(() => {
    service = new ShareLinkService();
  });

  afterEach(() => {
    service.clear();
  });

  it('1. Successfully creates share link and retrieves payload before consumption', () => {
    const created = service.createShareLink('owner-123', {
      encryptedBlob: 'encrypted-base64-blob',
      nonce: 'nonce-base64-1234',
      itemTitle: 'Wi-Fi Password',
      expiryHours: 24,
      oneTimeView: true,
    });

    expect(created.shareId).toBeDefined();
    expect(created.expiresAt).toBeDefined();

    const retrieved = service.getAndConsumeShareLink(created.shareId);
    expect(retrieved.encryptedBlob).toBe('encrypted-base64-blob');
    expect(retrieved.nonce).toBe('nonce-base64-1234');
  });

  it('2. Enforces One-Time View: second access attempt throws GoneException (410)', () => {
    const created = service.createShareLink('owner-123', {
      encryptedBlob: 'encrypted-base64-blob',
      nonce: 'nonce-base64-1234',
      expiryHours: 24,
      oneTimeView: true,
    });

    // First view consumes link
    const first = service.getAndConsumeShareLink(created.shareId);
    expect(first.encryptedBlob).toBe('encrypted-base64-blob');

    // Second view must fail with 410 Gone
    expect(() => service.getAndConsumeShareLink(created.shareId)).toThrow(GoneException);
  });

  it('3. Multi-view links allow multiple views until expiry', () => {
    const created = service.createShareLink('owner-123', {
      encryptedBlob: 'multi-view-blob',
      nonce: 'nonce-1234',
      expiryHours: 24,
      oneTimeView: false,
    });

    const v1 = service.getAndConsumeShareLink(created.shareId);
    const v2 = service.getAndConsumeShareLink(created.shareId);
    expect(v1.encryptedBlob).toBe('multi-view-blob');
    expect(v2.encryptedBlob).toBe('multi-view-blob');

    const ownerLinks = service.getOwnerShareLinks('owner-123');
    expect(ownerLinks[0].viewCount).toBe(2);
  });

  it('4. Owner manual revocation immediately blocks access', () => {
    const created = service.createShareLink('owner-123', {
      encryptedBlob: 'secret-blob',
      nonce: 'nonce-1234',
      expiryHours: 24,
      oneTimeView: true,
    });

    // Owner revokes link before any view
    const revokeRes = service.revokeShareLink('owner-123', created.shareId);
    expect(revokeRes.success).toBe(true);

    // Recipient attempt must throw GoneException
    expect(() => service.getAndConsumeShareLink(created.shareId)).toThrow(GoneException);
  });

  it('5. Rejects creation with missing encryptedBlob or nonce', () => {
    expect(() =>
      service.createShareLink('owner-123', {
        encryptedBlob: '',
        nonce: 'nonce',
        expiryHours: 24,
      }),
    ).toThrow(BadRequestException);
  });

  it('6. Zero-Knowledge Invariant: stores only ciphertext and metadata', () => {
    const created = service.createShareLink('owner-123', {
      encryptedBlob: 'ciphertext_only_AEAD',
      nonce: 'iv_only_12bytes',
      itemTitle: 'Production DB Credentials',
      expiryHours: 1,
      oneTimeView: true,
    });

    const ownerList = service.getOwnerShareLinks('owner-123');
    expect(ownerList.length).toBe(1);
    expect(ownerList[0].shareId).toBe(created.shareId);
    expect(ownerList[0].itemTitle).toBe('Production DB Credentials');

    // Verify plaintext secrets or keys never exist on the record
    const internalRecord = (service as any).links.get(created.shareId);
    expect(internalRecord).not.toHaveProperty('plaintext');
    expect(internalRecord).not.toHaveProperty('key');
    expect(internalRecord).not.toHaveProperty('decryptionKey');
  });
});
