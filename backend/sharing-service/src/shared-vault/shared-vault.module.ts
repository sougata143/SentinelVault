import { Module } from '@nestjs/common';
import { SharedVaultService } from './shared-vault.service';
import { SharedVaultController } from './shared-vault.controller';

@Module({
  controllers: [SharedVaultController],
  providers: [SharedVaultService],
  exports: [SharedVaultService],
})
export class SharedVaultModule {}
