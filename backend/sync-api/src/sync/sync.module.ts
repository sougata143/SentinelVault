import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';
import { EncryptedVaultItem } from './entities/encrypted-vault-item.entity';
import { VaultKey } from './entities/vault-key.entity';
import { JwtAuthGuard } from '../common/jwt-auth.guard';

@Module({
  imports: [
    TypeOrmModule.forFeature([EncryptedVaultItem, VaultKey]),
    /** Re-export JwtModule so JwtAuthGuard can inject JwtService.
     *  The module is configured globally in AppModule with JWT_SECRET;
     *  this import just makes the provider available locally. */
    JwtModule,
  ],
  controllers: [SyncController],
  providers: [SyncService, JwtAuthGuard],
  exports: [SyncService],
})
export class SyncModule {}
