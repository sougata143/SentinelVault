import {
  Injectable, NotFoundException, BadRequestException, ConflictException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { CreateInviteDto, AcceptInviteDto, DeclineInviteDto } from './share-invite.dto';

type InviteStatus = 'pending' | 'accepted' | 'declined' | 'revoked';

interface ShareInvite {
  inviteId: string;
  folderId: string;
  senderUserId: string;
  recipientUserId: string;
  /** Opaque signed payload bytes (base64url). */
  signedPayload: string;
  ed25519Signature: string;
  mldsaSignature: string;
  /** Pre-wrapped Folder Key ciphertext — only activated on acceptance + fingerprint confirm. */
  wrappedFolderKeyPayload: string;
  status: InviteStatus;
  /**
   * True only after the recipient explicitly confirms the sender's key
   * fingerprint out-of-band. The server gates key activation on this flag.
   */
  fingerprintVerified: boolean;
  createdAt: Date;
  respondedAt?: Date;
}

@Injectable()
export class ShareInviteService {
  private readonly invites = new Map<string, ShareInvite>();

  // ── Create ──────────────────────────────────────────────────────────────────

  createInvite(senderUserId: string, dto: CreateInviteDto): ShareInvite {
    // Prevent duplicate pending invites for the same (folder, recipient) pair
    for (const inv of this.invites.values()) {
      if (
        inv.folderId === dto.folderId &&
        inv.recipientUserId === dto.recipientUserId &&
        inv.status === 'pending'
      ) {
        throw new ConflictException('A pending invite already exists for this recipient and folder');
      }
    }

    const invite: ShareInvite = {
      inviteId: randomUUID(),
      folderId: dto.folderId,
      senderUserId,
      recipientUserId: dto.recipientUserId,
      signedPayload: dto.signedPayload,
      ed25519Signature: dto.ed25519Signature,
      mldsaSignature: dto.mldsaSignature,
      wrappedFolderKeyPayload: dto.wrappedFolderKeyPayload,
      status: 'pending',
      fingerprintVerified: false,
      createdAt: new Date(),
    };
    this.invites.set(invite.inviteId, invite);
    return invite;
  }

  // ── Accept ──────────────────────────────────────────────────────────────────

  /**
   * Accepts an invite ONLY when the recipient has explicitly confirmed the
   * sender's key fingerprint. The wrappedFolderKeyPayload is only made
   * available to callers after this gate passes.
   *
   * Security invariant: fingerprintVerified must be explicitly set by a
   * conscious user action — never auto-populated or defaulted to true.
   */
  acceptInvite(callerUserId: string, dto: AcceptInviteDto): ShareInvite {
    const invite = this.getInviteForRecipient(dto.inviteId, callerUserId);

    if (invite.status !== 'pending') {
      throw new BadRequestException(`Invite is already ${invite.status}`);
    }

    // Strict gate: fingerprint confirmation is non-negotiable.
    if (dto.fingerprintConfirmed !== 'true') {
      throw new BadRequestException(
        'Fingerprint must be confirmed out-of-band before accepting a share invite. ' +
        'Set fingerprintConfirmed to "true" only after visually verifying the safety number.',
      );
    }

    invite.fingerprintVerified = true;
    invite.status = 'accepted';
    invite.respondedAt = new Date();
    return invite;
  }

  // ── Decline ─────────────────────────────────────────────────────────────────

  declineInvite(callerUserId: string, dto: DeclineInviteDto): void {
    const invite = this.getInviteForRecipient(dto.inviteId, callerUserId);
    if (invite.status !== 'pending') {
      throw new BadRequestException(`Invite is already ${invite.status}`);
    }
    invite.status = 'declined';
    invite.respondedAt = new Date();
  }

  // ── List pending invites for a recipient ────────────────────────────────────

  listPendingForRecipient(recipientUserId: string): ShareInvite[] {
    return [...this.invites.values()].filter(
      (inv) => inv.recipientUserId === recipientUserId && inv.status === 'pending',
    );
  }

  // ── Get accepted invite details (for key retrieval) ──────────────────────────

  /**
   * Returns the wrapped Folder Key payload ONLY for an accepted, fingerprint-
   * verified invite belonging to the calling user.
   */
  getAcceptedInvitePayload(
    callerUserId: string,
    inviteId: string,
  ): { wrappedFolderKeyPayload: string } {
    const invite = this.getInviteForRecipient(inviteId, callerUserId);
    if (invite.status !== 'accepted' || !invite.fingerprintVerified) {
      throw new BadRequestException(
        'Wrapped key is only available for accepted, fingerprint-verified invites',
      );
    }
    return { wrappedFolderKeyPayload: invite.wrappedFolderKeyPayload };
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  private getInviteForRecipient(inviteId: string, recipientUserId: string): ShareInvite {
    const invite = this.invites.get(inviteId);
    if (!invite) throw new NotFoundException(`Invite ${inviteId} not found`);
    if (invite.recipientUserId !== recipientUserId) {
      throw new BadRequestException('Invite does not belong to the calling user');
    }
    return invite;
  }
}
