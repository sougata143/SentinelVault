import {
  Controller, Get, Post, Delete, Body, Param,
  HttpCode, HttpStatus, UseGuards,
} from '@nestjs/common';
import { ShareInviteService } from './share-invite.service';
import { CreateInviteDto, AcceptInviteDto, DeclineInviteDto } from './share-invite.dto';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser } from '../common/current-user.decorator';

/**
 * All endpoints are protected by JwtAuthGuard.
 * @CurrentUser() provides the server-verified caller id — cannot be spoofed
 * by any client-side header including x-user-id.
 */
@Controller('invites')
@UseGuards(JwtAuthGuard)
export class ShareInviteController {
  constructor(private readonly svc: ShareInviteService) {}

  /** POST /invites — Sender creates a share invitation. */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() callerId: string, @Body() dto: CreateInviteDto) {
    const invite = this.svc.createInvite(callerId, dto);
    return { ok: true, inviteId: invite.inviteId, createdAt: invite.createdAt };
  }

  /** GET /invites/pending — Recipient lists their pending invitations. */
  @Get('pending')
  listPending(@CurrentUser() callerId: string) {
    const pending = this.svc.listPendingForRecipient(callerId);
    return {
      ok: true,
      invites: pending.map((inv) => ({
        inviteId: inv.inviteId,
        folderId: inv.folderId,
        senderUserId: inv.senderUserId,
        signedPayload: inv.signedPayload,
        ed25519Signature: inv.ed25519Signature,
        mldsaSignature: inv.mldsaSignature,
        createdAt: inv.createdAt,
      })),
    };
  }

  /**
   * POST /invites/:id/accept — Recipient accepts after fingerprint confirmation.
   * The wrappedFolderKeyPayload is only activated after this step succeeds.
   */
  @Post(':id/accept')
  @HttpCode(HttpStatus.OK)
  accept(@CurrentUser() callerId: string, @Param('id') id: string, @Body() dto: AcceptInviteDto) {
    dto.inviteId = id;
    const invite = this.svc.acceptInvite(callerId, dto);
    return {
      ok: true,
      inviteId: invite.inviteId,
      status: invite.status,
      respondedAt: invite.respondedAt,
    };
  }

  /** GET /invites/:id/payload — Retrieve wrapped Folder Key after acceptance. */
  @Get(':id/payload')
  getPayload(@CurrentUser() callerId: string, @Param('id') id: string) {
    const result = this.svc.getAcceptedInvitePayload(callerId, id);
    return { ok: true, ...result };
  }

  /** DELETE /invites/:id — Recipient declines an invitation. */
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  decline(@CurrentUser() callerId: string, @Param('id') id: string, @Body() dto: DeclineInviteDto) {
    dto.inviteId = id;
    this.svc.declineInvite(callerId, dto);
    return { ok: true };
  }
}
