import { Test, TestingModule } from '@nestjs/testing';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { getRepositoryToken } from '@nestjs/typeorm';
import { UnauthorizedException, HttpException, HttpStatus } from '@nestjs/common';
import { AuthService } from '../src/auth/auth.service';
import { AuditService } from '../src/auth/audit.service';
import { UserRepository } from '../src/auth/user.repository';
import { RedisService } from '../src/auth/redis.service';
import { User } from '../src/auth/entities/user.entity';
import { WebauthnCredential } from '../src/auth/entities/webauthn-credential.entity';
import { AuditEventEntity } from '../src/auth/entities/audit-event.entity';
import { SessionEntity } from '../src/auth/entities/session.entity';
import { JwtAuthGuard } from '../src/common/jwt-auth.guard';
import * as crypto from 'crypto';

jest.mock('@simplewebauthn/server', () => ({
  generateRegistrationOptions: jest.fn(),
  verifyRegistrationResponse: jest.fn(),
  generateAuthenticationOptions: jest.fn(),
  verifyAuthenticationResponse: jest.fn(),
}));

const TEST_SECRET = 'test-jwt-secret-at-least-32-bytes-long!!';

class InMemoryUserRepo {
  private store = new Map<string, User>();

  createQueryBuilder() {
    const self = this;
    const builder = {
      _whereParams: {} as Record<string, string>,
      leftJoinAndSelect() { return this; },
      where(_str: string, params: Record<string, string>) { this._whereParams = params; return this; },
      async getOne(): Promise<User | null> {
        const uname = builder._whereParams['username'];
        if (!uname) return null;
        for (const u of self.store.values()) {
          if (u.username.toLowerCase() === uname.toLowerCase()) return u;
        }
        return null;
      },
    };
    return builder;
  }

  async findOne(opts: any): Promise<User | null> {
    if (opts?.where?.id) return this.store.get(opts.where.id) || null;
    return null;
  }

  async save(user: User): Promise<User> {
    if (!user.id) user.id = crypto.randomUUID();
    this.store.set(user.id, { ...user });
    return this.store.get(user.id)!;
  }
}

class InMemorySessionRepo {
  private store = new Map<string, SessionEntity>();

  create(dto: Partial<SessionEntity>): SessionEntity {
    const session = new SessionEntity();
    Object.assign(session, dto);
    if (!session.createdAt) session.createdAt = new Date();
    if (!session.lastActiveAt) session.lastActiveAt = new Date();
    return session;
  }

  async save(session: SessionEntity): Promise<SessionEntity> {
    if (!session.id) session.id = crypto.randomUUID();
    this.store.set(session.id, { ...session });
    return this.store.get(session.id)!;
  }

  async find(opts: any): Promise<SessionEntity[]> {
    const userId = opts?.where?.userId;
    const isRevoked = opts?.where?.isRevoked;
    const result: SessionEntity[] = [];
    for (const s of this.store.values()) {
      if (s.userId === userId && (isRevoked === undefined || s.isRevoked === isRevoked)) {
        result.push(s);
      }
    }
    return result;
  }

  async findOne(opts: any): Promise<SessionEntity | null> {
    const id = opts?.where?.id;
    const userId = opts?.where?.userId;
    const s = this.store.get(id);
    if (s && s.userId === userId) return s;
    return null;
  }
}

class InMemoryAuditRepo {
  private events: AuditEventEntity[] = [];
  create(dto: Partial<AuditEventEntity>): AuditEventEntity {
    const e = new AuditEventEntity();
    Object.assign(e, dto);
    e.id = crypto.randomUUID();
    e.timestamp = new Date();
    return e;
  }
  async save(e: AuditEventEntity): Promise<AuditEventEntity> {
    this.events.push(e);
    return e;
  }
  getEvents() { return this.events; }
}

describe('Session Revocation & Management', () => {
  let authService: AuthService;
  let jwtGuard: JwtAuthGuard;
  let redisService: RedisService;
  let auditRepo: InMemoryAuditRepo;
  let sessionRepo: InMemorySessionRepo;

  beforeEach(async () => {
    process.env.JWT_SECRET = TEST_SECRET;
    auditRepo = new InMemoryAuditRepo();
    sessionRepo = new InMemorySessionRepo();

    const module: TestingModule = await Test.createTestingModule({
      imports: [
        JwtModule.register({
          secret: TEST_SECRET,
          signOptions: { expiresIn: '24h' },
        }),
      ],
      providers: [
        AuthService,
        UserRepository,
        RedisService,
        AuditService,
        JwtAuthGuard,
        { provide: getRepositoryToken(User), useClass: InMemoryUserRepo },
        { provide: getRepositoryToken(WebauthnCredential), useValue: {} },
        { provide: getRepositoryToken(AuditEventEntity), useValue: auditRepo },
        { provide: getRepositoryToken(SessionEntity), useValue: sessionRepo },
      ],
    }).compile();

    authService = module.get<AuthService>(AuthService);
    jwtGuard = module.get<JwtAuthGuard>(JwtAuthGuard);
    redisService = module.get<RedisService>(RedisService);
  });

  it('creates a session with jti claim and logs audit event on login', async () => {
    const userId = 'user-uuid-123';
    const username = 'auditor@sentinelvault.io';

    const { session, token } = await authService.createSession(
      userId,
      username,
      'password',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );

    expect(session.id).toBeDefined();
    expect(session.deviceLabel).toBe('Chrome on macOS');
    expect(session.loginMethod).toBe('password');
    expect(session.isRevoked).toBe(false);

    // Audit log verification
    const auditEvents = auditRepo.getEvents();
    const createdEvent = auditEvents.find((e) => e.eventType === 'session_created');
    expect(createdEvent).toBeDefined();
    expect(createdEvent?.metadata?.deviceLabel).toBe('Chrome on macOS');

    // JwtAuthGuard verification
    const mockContext: any = {
      switchToHttp: () => ({
        getRequest: () => ({
          headers: { authorization: `Bearer ${token}` },
        }),
      }),
    };

    const canAccess = await jwtGuard.canActivate(mockContext);
    expect(canAccess).toBe(true);
  });

  it('rejects attempt to revoke active current session with HTTP 400', async () => {
    const userId = 'user-uuid-123';
    const { session } = await authService.createSession(userId, 'user@test.io', 'password');

    await expect(
      authService.revokeSession(userId, session.id, session.id),
    ).rejects.toThrow(HttpException);
  });

  it('revokes non-current session, pushes to Redis denylist, and causes JwtAuthGuard to reject token with 401', async () => {
    const userId = 'user-uuid-123';
    const username = 'user@test.io';

    // Session 1 (Current)
    const s1 = await authService.createSession(userId, username, 'password', 'Chrome on Windows');
    // Session 2 (Remote device to be revoked)
    const s2 = await authService.createSession(userId, username, 'password', 'SentinelVault iOS App');

    // Listing sessions
    const activeSessions = await authService.getUserSessions(userId, s1.session.id);
    expect(activeSessions.length).toBe(2);
    expect(activeSessions.find((s) => s.id === s1.session.id)?.isCurrent).toBe(true);
    expect(activeSessions.find((s) => s.id === s2.session.id)?.isCurrent).toBe(false);

    // Revoke Session 2
    const revokeResult = await authService.revokeSession(userId, s1.session.id, s2.session.id);
    expect(revokeResult.success).toBe(true);

    // Audit log check for revocation
    const auditEvents = auditRepo.getEvents();
    const revokedEvent = auditEvents.find((e) => e.eventType === 'session_revoked');
    expect(revokedEvent).toBeDefined();
    expect(revokedEvent?.metadata?.sessionId).toBe(s2.session.id);

    // Verify JwtAuthGuard now REJECTS token from Session 2
    const mockContextRevokedToken: any = {
      switchToHttp: () => ({
        getRequest: () => ({
          headers: { authorization: `Bearer ${s2.token}` },
        }),
      }),
    };

    await expect(
      jwtGuard.canActivate(mockContextRevokedToken),
    ).rejects.toThrow(UnauthorizedException);

    // Verify Session 1 token is still VALID
    const mockContextCurrentToken: any = {
      switchToHttp: () => ({
        getRequest: () => ({
          headers: { authorization: `Bearer ${s1.token}` },
        }),
      }),
    };

    const validAccess = await jwtGuard.canActivate(mockContextCurrentToken);
    expect(validAccess).toBe(true);
  });
});
