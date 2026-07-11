import { Module } from '@nestjs/common';
import { ShareInviteService } from './share-invite.service';
import { ShareInviteController } from './share-invite.controller';

@Module({
  providers: [ShareInviteService],
  controllers: [ShareInviteController],
})
export class ShareInviteModule {}
