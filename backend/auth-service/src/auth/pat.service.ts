import {
  Injectable, NotFoundException, BadRequestException, UnauthorizedException, ForbiddenException,
} from '@nestjs/common';
import { createHash, randomBytes, randomUUID } from 'crypto';
import { CreatePatDto, CreatePatResponseDto, PatListItemDto } from './pat.dto';
import { AuditService } from './audit.service';

export interface PatRecord {
  id: string;
  userId: string;
  name: string;
  tokenPrefix: string;
  tokenHash: string; // SHA-256
  scopes: string[];
  expiresAt?: Date;
  lastUsedAt?: Date;
  isRevoked: boolean;
  createdAt: Date;
}

@Injectable()
export class PatService {
  private readonly tokens = new Map<string, PatRecord>();

  constructor(private readonly auditService: AuditService) {}

  // ── Create PAT ─────────────────────────────────────────────────────────────

  async createToken(userId: string, dto: CreatePatDto): Promise<CreatePatResponseDto> {
    if (!dto.name || !dto.scopes || dto.scopes.length === 0) {
      throw new BadRequestException('Token name and at least one scope are required');
    }

    const secretHex = randomBytes(16).toString('hex'); // 32 hex chars
    const rawToken = `pat_sv_live_${secretHex}`;
    const tokenPrefix = `pat_sv_live_${secretHex.substring(0, 4)}...`;
    const tokenHash = createHash('sha256').update(rawToken).digest('hex');

    let expiresAt: Date | undefined;
    if (dto.expiryDays && dto.expiryDays > 0) {
      expiresAt = new Date(Date.now() + dto.expiryDays * 24 * 60 * 60 * 1000);
    }

    const record: PatRecord = {
      id: randomUUID(),
      userId,
      name: dto.name,
      tokenPrefix,
      tokenHash,
      scopes: dto.scopes,
      expiresAt,
      isRevoked: false,
      createdAt: new Date(),
    };

    this.tokens.set(record.id, record);

    // Audit Event
    await this.auditService.logEvent({
      userId,
      eventType: 'pat_created',
      metadata: { tokenId: record.id, name: dto.name, scopes: dto.scopes, expiryDays: dto.expiryDays },
    });

    return {
      id: record.id,
      name: record.name,
      rawToken, // RETURNED ONLY ONCE!
      tokenPrefix,
      scopes: record.scopes,
      expiresAt: expiresAt?.toISOString(),
      createdAt: record.createdAt.toISOString(),
    };
  }

  // ── Validate PAT Token Secret & Enforce Scope ──────────────────────────────

  async validateTokenAndScope(rawToken: string, requiredScope: string): Promise<PatRecord> {
    const tokenHash = createHash('sha256').update(rawToken).digest('hex');

    let matchedRecord: PatRecord | undefined;
    for (const record of this.tokens.values()) {
      if (record.tokenHash === tokenHash) {
        matchedRecord = record;
        break;
      }
    }

    if (!matchedRecord) {
      throw new UnauthorizedException('Invalid Personal Access Token');
    }

    if (matchedRecord.isRevoked) {
      throw new UnauthorizedException('This Personal Access Token has been revoked');
    }

    if (matchedRecord.expiresAt && new Date() > matchedRecord.expiresAt) {
      throw new UnauthorizedException('This Personal Access Token has expired');
    }

    if (!matchedRecord.scopes.includes(requiredScope) && !matchedRecord.scopes.includes('admin:*')) {
      throw new ForbiddenException(`Token lacks required scope: ${requiredScope}`);
    }

    matchedRecord.lastUsedAt = new Date();

    // Audit Event
    await this.auditService.logEvent({
      userId: matchedRecord.userId,
      eventType: 'pat_used',
      metadata: { tokenId: matchedRecord.id, requiredScope },
    });

    return matchedRecord;
  }

  // ── List PATs for User ─────────────────────────────────────────────────────

  getUserTokens(userId: string): PatListItemDto[] {
    const list: PatListItemDto[] = [];
    for (const token of this.tokens.values()) {
      if (token.userId === userId) {
        list.push({
          id: token.id,
          name: token.name,
          tokenPrefix: token.tokenPrefix,
          scopes: token.scopes,
          expiresAt: token.expiresAt?.toISOString(),
          lastUsedAt: token.lastUsedAt?.toISOString(),
          isRevoked: token.isRevoked,
          createdAt: token.createdAt.toISOString(),
        });
      }
    }
    return list;
  }

  // ── Revoke PAT ─────────────────────────────────────────────────────────────

  async revokeToken(userId: string, tokenId: string): Promise<{ success: boolean }> {
    const token = this.tokens.get(tokenId);
    if (!token || token.userId !== userId) {
      throw new NotFoundException(`Personal Access Token ${tokenId} not found`);
    }

    token.isRevoked = true;

    // Audit Event
    await this.auditService.logEvent({
      userId,
      eventType: 'pat_revoked',
      metadata: { tokenId: token.id, name: token.name },
    });

    return { success: true };
  }

  clear(): void {
    this.tokens.clear();
  }
}
