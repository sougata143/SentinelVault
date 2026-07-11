import { Module } from '@nestjs/common';
import { KeyDirectoryService } from './key-directory.service';
import { KeyDirectoryController } from './key-directory.controller';

@Module({
  providers: [KeyDirectoryService],
  controllers: [KeyDirectoryController],
  exports: [KeyDirectoryService],
})
export class KeyDirectoryModule {}
