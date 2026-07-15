import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ShareInviteService } from './share-invite.service';
import { ShareInviteController } from './share-invite.controller';
import { JwtAuthGuard } from '../common/jwt-auth.guard';

@Module({
  imports: [JwtModule],
  providers: [ShareInviteService, JwtAuthGuard],
  controllers: [ShareInviteController],
})
export class ShareInviteModule {}
