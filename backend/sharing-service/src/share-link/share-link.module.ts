import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ShareLinkController } from './share-link.controller';
import { ShareLinkService } from './share-link.service';
import { JwtAuthGuard } from '../common/jwt-auth.guard';

@Module({
  imports: [JwtModule],
  controllers: [ShareLinkController],
  providers: [ShareLinkService, JwtAuthGuard],
  exports: [ShareLinkService],
})
export class ShareLinkModule {}
