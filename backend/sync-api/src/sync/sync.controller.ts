import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
  Query,
  BadRequestException,
  HttpCode,
  HttpException,
  HttpStatus,
  UseGuards,
} from '@nestjs/common';
import { SyncService, EncryptedVaultItemDto } from './sync.service';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser } from '../common/current-user.decorator';

@Controller('sync')
@UseGuards(JwtAuthGuard)
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  // ── Multi-Vault Management Endpoints ────────────────────────────────────────

  /** GET /sync/vaults — returns all vault envelopes for the authenticated user. */
  @Get('vaults')
  async getUserVaults(@CurrentUser() userId: string) {
    return this.syncService.getUserVaults(userId);
  }

  /** POST /sync/vaults — creates a new vault envelope for the authenticated user. */
  @Post('vaults')
  @HttpCode(HttpStatus.CREATED)
  async createUserVault(
    @CurrentUser() userId: string,
    @Body() body: { name: string; salt: string; wrappedKey: string; recoverySalt?: string; recoveryWrappedKey?: string; isDefault?: boolean },
  ) {
    if (!body.salt || !body.wrappedKey) {
      throw new BadRequestException('Missing salt or wrappedKey in body');
    }
    return this.syncService.createUserVault(userId, body);
  }

  /** PUT /sync/vaults/:id — updates vault metadata or key wrapping. */
  @Put('vaults/:id')
  async updateUserVault(
    @CurrentUser() userId: string,
    @Param('id') vaultId: string,
    @Body() body: { name?: string; salt?: string; wrappedKey?: string },
  ) {
    return this.syncService.updateUserVault(userId, vaultId, body);
  }

  /** DELETE /sync/vaults/:id — deletes a user vault. */
  @Delete('vaults/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async deleteUserVault(
    @CurrentUser() userId: string,
    @Param('id') vaultId: string,
  ) {
    await this.syncService.deleteUserVault(userId, vaultId);
  }

  // ── Sync Pull & Push Endpoints ─────────────────────────────────────────────

  /** GET /sync/pull — returns encrypted vault items (optionally filtered by vaultId). */
  @Get('pull')
  async pull(
    @CurrentUser() userId: string,
    @Query('vaultId') vaultId?: string,
  ) {
    return this.syncService.pull(userId, vaultId);
  }

  /** POST /sync/push — upserts encrypted vault items. */
  @Post('push')
  @HttpCode(HttpStatus.OK)
  async push(
    @CurrentUser() userId: string,
    @Body() items: EncryptedVaultItemDto[],
    @Query('vaultId') targetVaultId?: string,
  ) {
    if (!Array.isArray(items)) {
      throw new BadRequestException('Body must be an array of vault items');
    }

    const conflicts = await this.syncService.push(userId, items, targetVaultId);
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

  // ── Legacy Single-Vault Endpoints (Backward Compatibility) ────────────────

  /** POST /sync/vault-key — stores default vault key envelope. */
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

  /** GET /sync/vault-key — retrieves default vault key envelope. */
  @Get('vault-key')
  async getVaultKey(@CurrentUser() userId: string) {
    const data = await this.syncService.getVaultKey(userId);
    if (!data) {
      throw new HttpException('Vault key not set', HttpStatus.NOT_FOUND);
    }
    return data;
  }
}
