import { EmergencyService } from '../src/emergency/emergency.service';
import { EmergencyContactEntity } from '../src/emergency/entities/emergency-contact.entity';
import { AccessRequestEntity } from '../src/emergency/entities/access-request.entity';

describe('EmergencyService State Machine Unit Tests', () => {
  let emergencyService: EmergencyService;
  let mockContactRepo: any;
  let mockRequestRepo: any;

  let contacts: EmergencyContactEntity[] = [];
  let requests: AccessRequestEntity[] = [];

  beforeEach(() => {
    contacts = [];
    requests = [];

    mockContactRepo = {
      create: jest.fn((dto) => ({
        id: 'contact-' + Math.random().toString(36).substring(7),
        createdAt: new Date(),
        ...dto,
      })),
      save: jest.fn(async (entity) => {
        const idx = contacts.findIndex((c) => c.id === entity.id);
        if (idx >= 0) contacts[idx] = entity;
        else contacts.push(entity);
        return entity;
      }),
      findOne: jest.fn(async (opts) => {
        const w = opts.where;
        return contacts.find((c) => {
          if (w.id && c.id !== w.id) return false;
          if (w.ownerUserId && c.ownerUserId !== w.ownerUserId) return false;
          if (w.contactUserId && c.contactUserId !== w.contactUserId) return false;
          if (w.status && c.status !== w.status) return false;
          return true;
        }) || null;
      }),
      find: jest.fn(async (opts) => {
        const w = opts.where;
        return contacts.filter((c) => {
          if (w.ownerUserId && c.ownerUserId !== w.ownerUserId) return false;
          if (w.contactUserId && c.contactUserId !== w.contactUserId) return false;
          if (w.status && c.status !== w.status) return false;
          return true;
        });
      }),
    };

    mockRequestRepo = {
      create: jest.fn((dto) => ({
        id: 'request-' + Math.random().toString(36).substring(7),
        requestedAt: new Date(),
        ...dto,
      })),
      save: jest.fn(async (entity) => {
        const idx = requests.findIndex((r) => r.id === entity.id);
        if (idx >= 0) requests[idx] = entity;
        else requests.push(entity);
        return entity;
      }),
      findOne: jest.fn(async (opts) => {
        const w = opts.where;
        return requests.find((r) => {
          if (w.id && r.id !== w.id) return false;
          if (w.contactId && r.contactId !== w.contactId) return false;
          if (w.ownerUserId && r.ownerUserId !== w.ownerUserId) return false;
          if (w.status && r.status !== w.status) return false;
          return true;
        }) || null;
      }),
      find: jest.fn(async (opts) => {
        const w = opts.where;
        return requests.filter((r) => {
          if (w.ownerUserId && r.ownerUserId !== w.ownerUserId) return false;
          if (w.contactId && r.contactId !== w.contactId) return false;
          if (w.status && r.status !== w.status) return false;
          return true;
        });
      }),
    };

    emergencyService = new EmergencyService(mockContactRepo, mockRequestRepo);
  });

  it('1. Owner designates trusted contact with waiting period', async () => {
    const contact = await emergencyService.addContact(
      'owner@sentinel.io',
      'contact@sentinel.io',
      'user-contact-1',
      72,
      'wrapped-vault-key-ciphertext',
    );

    expect(contact.id).toBeDefined();
    expect(contact.waitingPeriodHours).toBe(72);
    expect(contact.status).toBe('active');
    expect(contact.wrappedVaultKey).toBe('wrapped-vault-key-ciphertext');
  });

  it('2. Contact initiates access request starting waiting period (PENDING state)', async () => {
    const contact = await emergencyService.addContact(
      'owner@sentinel.io',
      'contact@sentinel.io',
      'user-contact-1',
      24,
      'wrapped-key-payload',
    );

    const req = await emergencyService.requestAccess('user-contact-1', contact.id);

    expect(req.status).toBe('pending');
    expect(req.ownerUserId).toBe('owner@sentinel.io');

    const expectedGrantsAt = req.requestedAt.getTime() + 24 * 3600 * 1000;
    expect(req.grantsAt.getTime()).toBeCloseTo(expectedGrantsAt, -3);
  });

  it('3. Owner denial halts pending request immediately (DENIED state)', async () => {
    const contact = await emergencyService.addContact(
      'owner@sentinel.io',
      'contact@sentinel.io',
      'user-contact-1',
      72,
      'wrapped-key-payload',
    );

    const req = await emergencyService.requestAccess('user-contact-1', contact.id);
    expect(req.status).toBe('pending');

    const deniedReq = await emergencyService.denyRequest('owner@sentinel.io', req.id);
    expect(deniedReq.status).toBe('denied');
    expect(deniedReq.resolvedAt).toBeDefined();

    // Query status should return denied and NO wrappedVaultKey
    const res = await emergencyService.getRequestStatus('user-contact-1', req.id);
    expect(res.request.status).toBe('denied');
    expect(res.wrappedVaultKey).toBeUndefined();
  });

  it('4. Access is granted ONLY after waiting period elapses without denial', async () => {
    const contact = await emergencyService.addContact(
      'owner@sentinel.io',
      'contact@sentinel.io',
      'user-contact-1',
      24,
      'wrapped-key-payload',
    );

    const req = await emergencyService.requestAccess('user-contact-1', contact.id);

    // Before waiting period elapses: should be pending & no key
    const preRes = await emergencyService.getRequestStatus('user-contact-1', req.id);
    expect(preRes.request.status).toBe('pending');
    expect(preRes.wrappedVaultKey).toBeUndefined();

    // Artificially simulate grantsAt passing
    req.grantsAt = new Date(Date.now() - 1000);

    const postRes = await emergencyService.getRequestStatus('user-contact-1', req.id);
    expect(postRes.request.status).toBe('granted');
    expect(postRes.wrappedVaultKey).toBe('wrapped-key-payload');
  });

  it('5. Owner revocation purges designation and cancels pending requests', async () => {
    const contact = await emergencyService.addContact(
      'owner@sentinel.io',
      'contact@sentinel.io',
      'user-contact-1',
      72,
      'wrapped-key-payload',
    );

    const req = await emergencyService.requestAccess('user-contact-1', contact.id);
    expect(req.status).toBe('pending');

    // Owner revokes contact
    await emergencyService.revokeContact('owner@sentinel.io', contact.id);

    const revokedContact = contacts.find((c) => c.id === contact.id);
    expect(revokedContact?.status).toBe('revoked');
    expect(revokedContact?.wrappedVaultKey).toBeUndefined();

    const cancelledReq = requests.find((r) => r.id === req.id);
    expect(cancelledReq?.status).toBe('cancelled');
  });
});
