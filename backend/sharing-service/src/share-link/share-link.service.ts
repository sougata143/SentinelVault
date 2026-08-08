import {
  Injectable, NotFoundException, BadRequestException, GoneException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { CreateShareLinkDto, ShareLinkPublicDto, ShareLinkOwnerDto } from './share-link.dto';

export interface ShareLinkRecord {
  shareId: string;
  ownerUserId: string;
  itemTitle?: string;
  encryptedBlob: string;
  nonce: string;
  oneTimeView: boolean;
  viewCount: number;
  isConsumed: boolean;
  isRevoked: boolean;
  expiresAt: Date;
  createdAt: Date;
}

@Injectable()
export class ShareLinkService {
  private readonly links = new Map<string, ShareLinkRecord>();

  // ── Create Share Link ───────────────────────────────────────────────────────

  createShareLink(ownerUserId: string, dto: CreateShareLinkDto): { shareId: string; expiresAt: string } {
    if (!dto.encryptedBlob || !dto.nonce) {
      throw new BadRequestException('encryptedBlob and nonce are required');
    }

    const hours = Math.max(1, Math.min(dto.expiryHours || 24, 168)); // 1 hour to 7 days
    const expiresAt = new Date(Date.now() + hours * 60 * 60 * 1000);
    const shareId = randomUUID();

    const record: ShareLinkRecord = {
      shareId,
      ownerUserId,
      itemTitle: dto.itemTitle,
      encryptedBlob: dto.encryptedBlob,
      nonce: dto.nonce,
      oneTimeView: dto.oneTimeView ?? true,
      viewCount: 0,
      isConsumed: false,
      isRevoked: false,
      expiresAt,
      createdAt: new Date(),
    };

    this.links.set(shareId, record);
    return { shareId, expiresAt: expiresAt.toISOString() };
  }

  // ── Recipient Unauthenticated Public Lookup ─────────────────────────────────

  getAndConsumeShareLink(shareId: string): ShareLinkPublicDto {
    const record = this.links.get(shareId);
    if (!record) {
      throw new NotFoundException('Share link not found');
    }

    if (record.isRevoked) {
      throw new GoneException('This share link has been revoked by the owner');
    }

    if (new Date() > record.expiresAt) {
      throw new GoneException('This share link has expired');
    }

    if (record.oneTimeView && record.isConsumed) {
      throw new GoneException('This one-time share link has already been viewed and destroyed');
    }

    // Record consumption state
    record.viewCount += 1;
    if (record.oneTimeView) {
      record.isConsumed = true;
    }

    return {
      shareId: record.shareId,
      encryptedBlob: record.encryptedBlob,
      nonce: record.nonce,
      expiresAt: record.expiresAt.toISOString(),
      oneTimeView: record.oneTimeView,
    };
  }

  // ── Owner Link Management ───────────────────────────────────────────────────

  getOwnerShareLinks(ownerUserId: string): ShareLinkOwnerDto[] {
    const ownerLinks: ShareLinkOwnerDto[] = [];
    for (const link of this.links.values()) {
      if (link.ownerUserId === ownerUserId) {
        ownerLinks.push({
          shareId: link.shareId,
          itemTitle: link.itemTitle,
          expiresAt: link.expiresAt.toISOString(),
          oneTimeView: link.oneTimeView,
          viewCount: link.viewCount,
          isConsumed: link.isConsumed,
          isRevoked: link.isRevoked,
          createdAt: link.createdAt.toISOString(),
        });
      }
    }
    return ownerLinks;
  }

  revokeShareLink(ownerUserId: string, shareId: string): { success: boolean } {
    const link = this.links.get(shareId);
    if (!link || link.ownerUserId !== ownerUserId) {
      throw new NotFoundException(`Share link ${shareId} not found`);
    }

    link.isRevoked = true;
    return { success: true };
  }

  clear(): void {
    this.links.clear();
  }
}
