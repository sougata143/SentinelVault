import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { KeyDirectoryService } from './key-directory.service';
import { KeyDirectoryController } from './key-directory.controller';
import { JwtAuthGuard } from '../common/jwt-auth.guard';

@Module({
  imports: [JwtModule],
  providers: [KeyDirectoryService, JwtAuthGuard],
  controllers: [KeyDirectoryController],
  exports: [KeyDirectoryService],
})
export class KeyDirectoryModule {}
