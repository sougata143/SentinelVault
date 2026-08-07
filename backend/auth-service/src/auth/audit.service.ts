import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuditEventEntity } from './entities/audit-event.entity';

export interface LogEventParams {
  userId: string;
  eventType: string;
  ipAddress?: string;
  userAgent?: string;
  metadata?: Record<string, any>;
}

@Injectable()
export class AuditService {
  constructor(
    @InjectRepository(AuditEventEntity)
    private readonly auditRepo: Repository<AuditEventEntity>,
  ) {}

  /**
   * Logs a security audit event.
   * Enforces strict Zero-Knowledge Sanitization — strips any sensitive keys
   * (passwords, tokens, plaintext, secrets) before saving.
   */
  async logEvent(params: LogEventParams): Promise<AuditEventEntity> {
    const sanitizedMeta = this.sanitizeMetadata(params.metadata);

    const event = this.auditRepo.create({
      userId: params.userId,
      eventType: params.eventType,
      ipAddress: params.ipAddress,
      userAgent: params.userAgent,
      metadata: sanitizedMeta,
    });

    return await this.auditRepo.save(event);
  }

  /**
   * Retrieves chronological audit logs for a given user.
   */
  async getUserAuditLogs(
    userId: string,
    eventType?: string,
    limit = 50,
    offset = 0,
  ): Promise<{ events: AuditEventEntity[]; total: number }> {
    const qb = this.auditRepo
      .createQueryBuilder('event')
      .where('event.userId = :userId', { userId })
      .orderBy('event.timestamp', 'DESC')
      .take(limit)
      .skip(offset);

    if (eventType && eventType !== 'all') {
      qb.andWhere('event.eventType = :eventType', { eventType });
    }

    const [events, total] = await qb.getManyAndCount();
    return { events, total };
  }

  /**
   * Zero-Knowledge Sanitizer: Removes sensitive cryptographic or personal fields.
   */
  private sanitizeMetadata(meta?: Record<string, any>): Record<string, any> | undefined {
    if (!meta) return undefined;
    const forbidden = [
      'password',
      'plaintext',
      'secret',
      'seedphrase',
      'privatekey',
      'token',
      'content',
      'masterkey',
      'vaultkey',
    ];

    const clean: Record<string, any> = {};
    for (const [key, val] of Object.entries(meta)) {
      const lowerKey = key.toLowerCase();
      if (!forbidden.some((f) => lowerKey.includes(f))) {
        clean[key] = val;
      }
    }
    return clean;
  }
}
