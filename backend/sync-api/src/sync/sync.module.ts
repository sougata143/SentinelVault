import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';
import { EncryptedVaultItem } from './entities/encrypted-vault-item.entity';
import { VaultKey } from './entities/vault-key.entity';

@Module({
  imports: [TypeOrmModule.forFeature([EncryptedVaultItem, VaultKey])],
  controllers: [SyncController],
  providers: [SyncService],
  exports: [SyncService],
})
export class SyncModule {}
