import {
  Controller,
  Get,
  Post,
  Body,
  BadRequestException,
  HttpCode,
  HttpException,
  HttpStatus,
  UseGuards,
} from '@nestjs/common';
import { SyncService, EncryptedVaultItemDto } from './sync.service';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser } from '../common/current-user.decorator';

/**
 * SyncController
 *
 * All endpoints are protected by JwtAuthGuard, which:
 *   1. Extracts the `Authorization: Bearer <token>` header
 *   2. Verifies the token signature against JWT_SECRET
 *   3. Attaches `req.user = { id: payload.sub, username }` on success
 *   4. Rejects with 401 UNAUTHORIZED if the token is absent, malformed, or expired
 *
 * @CurrentUser() then provides the server-verified user id — the client cannot
 * override this value by sending an `x-user-id` header or any other means.
 */
@Controller('sync')
@UseGuards(JwtAuthGuard)
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  /** GET /sync/pull — returns all encrypted vault items for the authenticated user. */
  @Get('pull')
  async pull(@CurrentUser() userId: string) {
    return this.syncService.pull(userId);
  }

  /** POST /sync/push — upserts encrypted vault items for the authenticated user. */
  @Post('push')
  @HttpCode(HttpStatus.OK)
  async push(
    @CurrentUser() userId: string,
    @Body() items: EncryptedVaultItemDto[],
  ) {
    if (!Array.isArray(items)) {
      throw new BadRequestException('Body must be an array of vault items');
    }

    const conflicts = await this.syncService.push(userId, items);
    if (conflicts) {
      throw new HttpException(
        {
          statusCode: HttpStatus.CONFLICT,
          message: 'Version conflict detected',
          conflicts,
        },
        HttpStatus.CONFLICT,
      );
    }

    return { success: true };
  }

  /** POST /sync/vault-key — stores the server-side wrapped vault key envelope. */
  @Post('vault-key')
  @HttpCode(HttpStatus.OK)
  async saveVaultKey(
    @CurrentUser() userId: string,
    @Body() body: { salt: string; wrappedKey: string; recoverySalt?: string; recoveryWrappedKey?: string },
  ) {
    if (!body.salt || !body.wrappedKey) {
      throw new BadRequestException('Missing salt or wrappedKey in body');
    }
    await this.syncService.saveVaultKey(
      userId,
      body.salt,
      body.wrappedKey,
      body.recoverySalt,
      body.recoveryWrappedKey,
    );
    return { success: true };
  }

  /** GET /sync/vault-key — retrieves the wrapped vault key envelope for the authenticated user. */
  @Get('vault-key')
  async getVaultKey(@CurrentUser() userId: string) {
    const data = await this.syncService.getVaultKey(userId);
    if (!data) {
      throw new HttpException('Vault key not set', HttpStatus.NOT_FOUND);
    }
    return data;
  }
}
