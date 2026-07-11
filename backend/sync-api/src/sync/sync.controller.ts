import {
  Controller,
  Get,
  Post,
  Body,
  Headers,
  BadRequestException,
  HttpCode,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { SyncService, EncryptedVaultItemDto } from './sync.service';

@Controller('sync')
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  @Get('pull')
  async pull(@Headers('x-user-id') userId?: string) {
    if (!userId) {
      throw new BadRequestException('Missing x-user-id header');
    }
    return this.syncService.pull(userId);
  }

  @Post('push')
  @HttpCode(HttpStatus.OK)
  async push(
    @Headers('x-user-id') userId: string | undefined,
    @Body() items: EncryptedVaultItemDto[],
  ) {
    if (!userId) {
      throw new BadRequestException('Missing x-user-id header');
    }
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

  @Post('vault-key')
  @HttpCode(HttpStatus.OK)
  async saveVaultKey(
    @Headers('x-user-id') userId: string | undefined,
    @Body() body: { salt: string; wrappedKey: string; recoverySalt?: string; recoveryWrappedKey?: string },
  ) {
    if (!userId) {
      throw new BadRequestException('Missing x-user-id header');
    }
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

  @Get('vault-key')
  async getVaultKey(@Headers('x-user-id') userId?: string) {
    if (!userId) {
      throw new BadRequestException('Missing x-user-id header');
    }
    const data = await this.syncService.getVaultKey(userId);
    if (!data) {
      throw new HttpException('Vault key not set', HttpStatus.NOT_FOUND);
    }
    return data;
  }
}

