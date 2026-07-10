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
}
