// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Key Directory Controller
// ─────────────────────────────────────────────────────────────────────────────
import {
  Controller, Get, Post, Delete, Body, Param, Req,
  HttpCode, HttpStatus, UseGuards,
} from '@nestjs/common';
import { KeyDirectoryService } from './key-directory.service';
import {
  PublishKeyBundleDto,
  PublishWrappedKeysDto,
  RevokeRecipientDto,
  FetchWrappedKeyDto,
} from './key-directory.dto';

// Stub guard – wire in real JWT guard from auth-service in production.
// Every mutating endpoint must validate the caller's identity.
import { Request } from 'express';

/** Extracts userId from a validated JWT claim (stub for scaffolding). */
function callerUserId(req: Request): string {
  // In production: (req.user as { sub: string }).sub
  return (req.headers['x-user-id'] as string) ?? 'anonymous';
}

@Controller('key-directory')
export class KeyDirectoryController {
  constructor(private readonly svc: KeyDirectoryService) {}

  // ── POST /key-directory/keys ──────────────────────────────────────────────
  // Publish or rotate the caller's public key bundle.
  @Post('keys')
  @HttpCode(HttpStatus.OK)
  publishKeyBundle(
    @Req() req: Request,
    @Body() dto: PublishKeyBundleDto,
  ) {
    // Ensure userId in body matches authenticated caller
    const caller = callerUserId(req);
    if (dto.userId !== caller) {
      return { ok: false, error: 'userId mismatch' };
    }
    const bundle = this.svc.publishKeyBundle(dto);
    return {
      ok: true,
      keyFingerprint: bundle.keyFingerprint,
      updatedAt: bundle.updatedAt.toISOString(),
    };
  }

  // ── GET /key-directory/keys/:userId ──────────────────────────────────────
  // Fetch another user's public key bundle.
  // IMPORTANT: callers MUST verify keyFingerprint out-of-band before trusting.
  @Get('keys/:userId')
  getKeyBundle(@Param('userId') userId: string) {
    const b = this.svc.getKeyBundle(userId);
    return {
      userId: b.userId,
      x25519PublicKey: b.x25519PublicKey,
      ed25519PublicKey: b.ed25519PublicKey,
      mlkemEncapsulationKey: b.mlkemEncapsulationKey,
      mldsaVerifyingKey: b.mldsaVerifyingKey,
      keyFingerprint: b.keyFingerprint,
      updatedAt: b.updatedAt.toISOString(),
    };
  }

  // ── POST /key-directory/wrapped-keys ─────────────────────────────────────
  // Publish per-recipient ciphertext-wrapped Folder Keys for a folder.
  @Post('wrapped-keys')
  @HttpCode(HttpStatus.OK)
  publishWrappedKeys(
    @Req() req: Request,
    @Body() dto: PublishWrappedKeysDto,
  ) {
    this.svc.publishWrappedKeys(callerUserId(req), dto);
    return { ok: true };
  }

  // ── GET /key-directory/wrapped-keys/:folderId ─────────────────────────────
  // Fetch the calling user's own wrapped Folder Key for a folder.
  @Get('wrapped-keys/:folderId')
  fetchWrappedKey(
    @Req() req: Request,
    @Param('folderId') folderId: string,
  ) {
    const record = this.svc.fetchWrappedKey(
      callerUserId(req),
      { folderId } satisfies FetchWrappedKeyDto,
    );
    return { ok: true, record };
  }

  // ── DELETE /key-directory/wrapped-keys/revoke ────────────────────────────
  // Revoke a recipient and publish the new Folder Key version.
  @Delete('wrapped-keys/revoke')
  @HttpCode(HttpStatus.OK)
  revokeRecipient(
    @Req() req: Request,
    @Body() dto: RevokeRecipientDto,
  ) {
    this.svc.revokeRecipient(callerUserId(req), dto);
    return { ok: true, newKeyVersion: dto.newKeyVersion };
  }

  // ── GET /key-directory/wrapped-keys/:folderId/version ────────────────────
  @Get('wrapped-keys/:folderId/version')
  getCurrentVersion(@Param('folderId') folderId: string) {
    const v = this.svc.getCurrentKeyVersion(folderId);
    return { folderId, keyVersion: v };
  }
}
