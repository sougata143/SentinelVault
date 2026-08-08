import { PatService } from '../src/auth/pat.service';
import { AuditService } from '../src/auth/audit.service';
import { ForbiddenException, UnauthorizedException, NotFoundException } from '@nestjs/common';

describe('PatService Security & Scope Enforcement Tests', () => {
  let patService: PatService;
  let auditService: AuditService;
  let mockAuditRepo: any;

  beforeEach(() => {
    mockAuditRepo = {
      create: jest.fn().mockImplementation((val) => val),
      save: jest.fn().mockImplementation(async (val) => ({ id: 'audit-123', ...val, timestamp: new Date() })),
    };
    auditService = new AuditService(mockAuditRepo);
    patService = new PatService(auditService);
  });

  afterEach(() => {
    patService.clear();
  });

  it('1. Creates PAT, returns raw token ONCE, and stores only SHA-256 hash', async () => {
    const created = await patService.createToken('user-alice', {
      name: 'CI/CD Pipeline Bot',
      scopes: ['vault:read'],
      expiryDays: 30,
    });

    expect(created.id).toBeDefined();
    expect(created.rawToken).toContain('pat_sv_live_');
    expect(created.tokenPrefix).toContain('pat_sv_live_');

    // Verify rawToken is NOT saved on internal record (only tokenHash)
    const internalRecord = (patService as any).tokens.get(created.id);
    expect(internalRecord).not.toHaveProperty('rawToken');
    expect(internalRecord.tokenHash).toBeDefined();

    expect(mockAuditRepo.save).toHaveBeenCalled();
  });

  it('2. Scope Enforcement: vault:read token succeeds on vault:read but throws Forbidden (403) on vault:write', async () => {
    const created = await patService.createToken('user-alice', {
      name: 'Read Only Script',
      scopes: ['vault:read'],
    });

    // Valid scope access succeeds
    const validRec = await patService.validateTokenAndScope(created.rawToken, 'vault:read');
    expect(validRec.userId).toBe('user-alice');

    // Invalid scope access throws 403 Forbidden
    await expect(
      patService.validateTokenAndScope(created.rawToken, 'vault:write'),
    ).rejects.toThrow(ForbiddenException);
  });

  it('3. Immediate Revocation: revoking token causes immediate next access failure (401)', async () => {
    const created = await patService.createToken('user-alice', {
      name: 'Ephemeral Bot',
      scopes: ['vault:read', 'vault:write'],
    });

    // Access before revocation succeeds
    await patService.validateTokenAndScope(created.rawToken, 'vault:read');

    // User revokes token
    const revokeRes = await patService.revokeToken('user-alice', created.id);
    expect(revokeRes.success).toBe(true);

    // Next access attempt MUST throw 401 Unauthorized
    await expect(
      patService.validateTokenAndScope(created.rawToken, 'vault:read'),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('4. Expiry Enforcement: expired tokens throw 401 Unauthorized', async () => {
    const created = await patService.createToken('user-alice', {
      name: 'Expired Token',
      scopes: ['vault:read'],
      expiryDays: 1,
    });

    // Artificially expire the token record
    const internalRecord = (patService as any).tokens.get(created.id);
    internalRecord.expiresAt = new Date(Date.now() - 10000);

    await expect(
      patService.validateTokenAndScope(created.rawToken, 'vault:read'),
    ).rejects.toThrow(UnauthorizedException);
  });
});
