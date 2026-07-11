import {
  Controller, Get, Post, Delete, Body, Param, Req,
  HttpCode, HttpStatus,
} from '@nestjs/common';
import { Request } from 'express';
import { ShareInviteService } from './share-invite.service';
import { CreateInviteDto, AcceptInviteDto, DeclineInviteDto } from './share-invite.dto';

function callerUserId(req: Request): string {
  return (req.headers['x-user-id'] as string) ?? 'anonymous';
}

@Controller('invites')
export class ShareInviteController {
  constructor(private readonly svc: ShareInviteService) {}

  /** POST /invites — Sender creates a share invitation. */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Req() req: Request, @Body() dto: CreateInviteDto) {
    const invite = this.svc.createInvite(callerUserId(req), dto);
    return { ok: true, inviteId: invite.inviteId, createdAt: invite.createdAt };
  }

  /** GET /invites/pending — Recipient lists their pending invitations. */
  @Get('pending')
  listPending(@Req() req: Request) {
    const pending = this.svc.listPendingForRecipient(callerUserId(req));
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
  accept(@Req() req: Request, @Param('id') id: string, @Body() dto: AcceptInviteDto) {
    dto.inviteId = id;
    const invite = this.svc.acceptInvite(callerUserId(req), dto);
    return {
      ok: true,
      inviteId: invite.inviteId,
      status: invite.status,
      respondedAt: invite.respondedAt,
    };
  }

  /** GET /invites/:id/payload — Retrieve wrapped Folder Key after acceptance. */
  @Get(':id/payload')
  getPayload(@Req() req: Request, @Param('id') id: string) {
    const result = this.svc.getAcceptedInvitePayload(callerUserId(req), id);
    return { ok: true, ...result };
  }

  /** DELETE /invites/:id — Recipient declines an invitation. */
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  decline(@Req() req: Request, @Param('id') id: string, @Body() dto: DeclineInviteDto) {
    dto.inviteId = id;
    this.svc.declineInvite(callerUserId(req), dto);
    return { ok: true };
  }
}
