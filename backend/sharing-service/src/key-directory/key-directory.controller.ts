// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Key Directory Controller
// ─────────────────────────────────────────────────────────────────────────────
import {
  Controller, Get, Post, Delete, Body, Param,
  HttpCode, HttpStatus, UseGuards,
} from '@nestjs/common';
import { KeyDirectoryService } from './key-directory.service';
import {
  PublishKeyBundleDto,
  PublishWrappedKeysDto,
  RevokeRecipientDto,
  FetchWrappedKeyDto,
} from './key-directory.dto';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser } from '../common/current-user.decorator';

/**
 * All mutating and user-scoped read endpoints are protected by JwtAuthGuard.
 * The guard verifies the Bearer token and attaches req.user = { id, username }.
 * @CurrentUser() extracts the server-verified user id — it cannot be spoofed
 * by an `x-user-id` header or any other client-controlled value.
 */
@Controller('key-directory')
@UseGuards(JwtAuthGuard)
export class KeyDirectoryController {
  constructor(private readonly svc: KeyDirectoryService) {}

  // ── POST /key-directory/keys ──────────────────────────────────────────────
  // Publish or rotate the caller's public key bundle.
  @Post('keys')
  @HttpCode(HttpStatus.OK)
  publishKeyBundle(
    @CurrentUser() callerId: string,
    @Body() dto: PublishKeyBundleDto,
  ) {
    // Ensure userId in body matches authenticated caller
    if (dto.userId !== callerId) {
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
    @CurrentUser() callerId: string,
    @Body() dto: PublishWrappedKeysDto,
  ) {
    this.svc.publishWrappedKeys(callerId, dto);
    return { ok: true };
  }

  // ── GET /key-directory/wrapped-keys/:folderId ─────────────────────────────
  // Fetch the calling user's own wrapped Folder Key for a folder.
  @Get('wrapped-keys/:folderId')
  fetchWrappedKey(
    @CurrentUser() callerId: string,
    @Param('folderId') folderId: string,
  ) {
    const record = this.svc.fetchWrappedKey(
      callerId,
      { folderId } satisfies FetchWrappedKeyDto,
    );
    return { ok: true, record };
  }

  // ── DELETE /key-directory/wrapped-keys/revoke ────────────────────────────
  // Revoke a recipient and publish the new Folder Key version.
  @Delete('wrapped-keys/revoke')
  @HttpCode(HttpStatus.OK)
  revokeRecipient(
    @CurrentUser() callerId: string,
    @Body() dto: RevokeRecipientDto,
  ) {
    this.svc.revokeRecipient(callerId, dto);
    return { ok: true, newKeyVersion: dto.newKeyVersion };
  }

  // ── GET /key-directory/wrapped-keys/:folderId/version ────────────────────
  @Get('wrapped-keys/:folderId/version')
  getCurrentVersion(@Param('folderId') folderId: string) {
    const v = this.svc.getCurrentKeyVersion(folderId);
    return { folderId, keyVersion: v };
  }
}
