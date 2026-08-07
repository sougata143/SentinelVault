import { Injectable, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { EmergencyContactEntity } from './entities/emergency-contact.entity';
import { AccessRequestEntity } from './entities/access-request.entity';

@Injectable()
export class EmergencyService {
  private readonly logger = new Logger(EmergencyService.name);

  constructor(
    @InjectRepository(EmergencyContactEntity)
    private readonly contactRepo: Repository<EmergencyContactEntity>,
    @InjectRepository(AccessRequestEntity)
    private readonly requestRepo: Repository<AccessRequestEntity>,
  ) {}

  /**
   * Designates a new trusted contact with owner-configured waiting period.
   */
  async addContact(
    ownerUserId: string,
    contactEmail: string,
    contactUserId: string,
    waitingPeriodHours = 72,
    wrappedVaultKey?: string,
  ): Promise<EmergencyContactEntity> {
    const existing = await this.contactRepo.findOne({
      where: { ownerUserId, contactUserId, status: 'active' },
    });

    if (existing) {
      existing.waitingPeriodHours = waitingPeriodHours;
      if (wrappedVaultKey) existing.wrappedVaultKey = wrappedVaultKey;
      return await this.contactRepo.save(existing);
    }

    const contact = this.contactRepo.create({
      ownerUserId,
      contactEmail,
      contactUserId,
      waitingPeriodHours,
      wrappedVaultKey,
      status: 'active',
    });

    return await this.contactRepo.save(contact);
  }

  async getContactsForOwner(ownerUserId: string): Promise<EmergencyContactEntity[]> {
    return await this.contactRepo.find({
      where: { ownerUserId, status: 'active' },
      order: { createdAt: 'DESC' },
    });
  }

  async getContactsForContactUser(contactUserId: string): Promise<EmergencyContactEntity[]> {
    return await this.contactRepo.find({
      where: { contactUserId, status: 'active' },
      order: { createdAt: 'DESC' },
    });
  }

  async revokeContact(ownerUserId: string, contactId: string): Promise<void> {
    const contact = await this.contactRepo.findOne({
      where: { id: contactId, ownerUserId },
    });

    if (!contact) {
      throw new HttpException('Contact not found', HttpStatus.NOT_FOUND);
    }

    contact.status = 'revoked';
    contact.wrappedVaultKey = undefined;
    await this.contactRepo.save(contact);

    // Cancel any pending requests
    const pending = await this.requestRepo.find({
      where: { contactId, status: 'pending' },
    });

    for (const req of pending) {
      req.status = 'cancelled';
      req.resolvedAt = new Date();
      await this.requestRepo.save(req);
    }
  }

  /**
   * Submits an emergency access request, starting the waiting period.
   */
  async requestAccess(contactUserId: string, contactId: string): Promise<AccessRequestEntity> {
    const contact = await this.contactRepo.findOne({
      where: { id: contactId, contactUserId, status: 'active' },
    });

    if (!contact) {
      throw new HttpException('Active emergency contact designation not found', HttpStatus.NOT_FOUND);
    }

    const existingPending = await this.requestRepo.findOne({
      where: { contactId, status: 'pending' },
    });

    if (existingPending) {
      return existingPending;
    }

    const now = new Date();
    const grantsAt = new Date(now.getTime() + contact.waitingPeriodHours * 3600 * 1000);

    const req = this.requestRepo.create({
      contactId: contact.id,
      ownerUserId: contact.ownerUserId,
      contactUserId: contact.contactUserId,
      status: 'pending',
      requestedAt: now,
      grantsAt,
    });

    const saved = await this.requestRepo.save(req);
    this.logger.log(`[EMERGENCY_REQUEST_INIT] Owner: ${contact.ownerUserId}, Contact: ${contactUserId}, GrantsAt: ${grantsAt.toISOString()}`);
    return saved;
  }

  /**
   * Owner denies a pending access request.
   */
  async denyRequest(ownerUserId: string, requestId: string): Promise<AccessRequestEntity> {
    const req = await this.requestRepo.findOne({
      where: { id: requestId, ownerUserId },
    });

    if (!req) {
      throw new HttpException('Request not found', HttpStatus.NOT_FOUND);
    }

    if (req.status !== 'pending') {
      throw new HttpException('Request is not pending', HttpStatus.BAD_REQUEST);
    }

    req.status = 'denied';
    req.resolvedAt = new Date();
    const saved = await this.requestRepo.save(req);
    this.logger.log(`[EMERGENCY_REQUEST_DENIED] Owner: ${ownerUserId}, RequestId: ${requestId}`);
    return saved;
  }

  /**
   * Checks request status and returns wrapped Vault Key if granted or matured.
   */
  async getRequestStatus(userId: string, requestId: string): Promise<{ request: AccessRequestEntity; wrappedVaultKey?: string }> {
    const req = await this.requestRepo.findOne({
      where: { id: requestId },
    });

    if (!req || (req.ownerUserId !== userId && req.contactUserId !== userId)) {
      throw new HttpException('Request not found or access denied', HttpStatus.NOT_FOUND);
    }

    // Evaluate waiting period maturity
    if (req.status === 'pending') {
      const now = new Date();
      if (now >= req.grantsAt) {
        req.status = 'granted';
        req.resolvedAt = now;
        await this.requestRepo.save(req);
        this.logger.log(`[EMERGENCY_REQUEST_GRANTED_MATURED] RequestId: ${requestId}`);
      }
    }

    let wrappedVaultKey: string | undefined;
    if (req.status === 'granted') {
      const contact = await this.contactRepo.findOne({ where: { id: req.contactId } });
      wrappedVaultKey = contact?.wrappedVaultKey;
    }

    return { request: req, wrappedVaultKey };
  }

  async getPendingRequestsForOwner(ownerUserId: string): Promise<AccessRequestEntity[]> {
    return await this.requestRepo.find({
      where: { ownerUserId, status: 'pending' },
      order: { requestedAt: 'DESC' },
    });
  }
}
