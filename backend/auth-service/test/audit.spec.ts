import { AuditService } from '../src/auth/audit.service';
import { AuditEventEntity } from '../src/auth/entities/audit-event.entity';

describe('AuditService Unit Tests', () => {
  let auditService: AuditService;
  let mockRepo: any;
  let savedEvents: AuditEventEntity[] = [];

  beforeEach(() => {
    savedEvents = [];
    mockRepo = {
      create: jest.fn((dto) => ({
        id: 'mock-uuid-' + Math.random().toString(36).substring(7),
        timestamp: new Date(),
        ...dto,
      })),
      save: jest.fn(async (entity) => {
        savedEvents.push(entity);
        return entity;
      }),
      createQueryBuilder: jest.fn(() => {
        let userIdFilter = '';
        let eventTypeFilter = '';
        const builder: any = {};
        builder.where = jest.fn((clause: string, params: any) => {
          userIdFilter = params.userId;
          return builder;
        });
        builder.orderBy = jest.fn(() => builder);
        builder.take = jest.fn(() => builder);
        builder.skip = jest.fn(() => builder);
        builder.andWhere = jest.fn((clause: string, params: any) => {
          eventTypeFilter = params.eventType;
          return builder;
        });
        builder.getManyAndCount = jest.fn(async () => {
          let filtered = savedEvents.filter((e) => e.userId === userIdFilter);
          if (eventTypeFilter && eventTypeFilter !== 'all') {
            filtered = filtered.filter((e) => e.eventType === eventTypeFilter);
          }
          return [filtered, filtered.length];
        });
        return builder;
      }),
    };

    auditService = new AuditService(mockRepo);
  });

  it('should log audit event and sanitize sensitive keys from metadata', async () => {
    const event = await auditService.logEvent({
      userId: 'user-123',
      eventType: 'login_success',
      metadata: {
        method: 'srp-6a',
        password: 'SuperSecretPassword123!',
        secret: 'raw-secret-key',
        folderId: 'folder-456',
      },
    });

    expect(event).toBeDefined();
    expect(event.userId).toBe('user-123');
    expect(event.eventType).toBe('login_success');
    expect(event.metadata).toBeDefined();
    expect(event.metadata?.method).toBe('srp-6a');
    expect(event.metadata?.folderId).toBe('folder-456');

    // Security Invariant: Plaintext password & secrets MUST be stripped
    expect(event.metadata?.password).toBeUndefined();
    expect(event.metadata?.secret).toBeUndefined();
  });

  it('should query user audit logs with optional eventType filter', async () => {
    await auditService.logEvent({ userId: 'user-1', eventType: 'login_success' });
    await auditService.logEvent({ userId: 'user-1', eventType: 'vault_export' });
    await auditService.logEvent({ userId: 'user-2', eventType: 'login_failure' });

    const allUser1 = await auditService.getUserAuditLogs('user-1');
    expect(allUser1.total).toBe(2);

    const filteredExports = await auditService.getUserAuditLogs('user-1', 'vault_export');
    expect(filteredExports.total).toBe(1);
    expect(filteredExports.events[0].eventType).toBe('vault_export');
  });
});
