import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { TypeOrmModule } from '@nestjs/typeorm';
import { KeyDirectoryService } from './key-directory.service';
import { KeyDirectoryController } from './key-directory.controller';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { KeyBundle } from './entities/key-bundle.entity';
import { WrappedKeyVersion } from './entities/wrapped-key-version.entity';
import { WrappedKeyRecipient } from './entities/wrapped-key-recipient.entity';

@Module({
  imports: [
    JwtModule,
    // Wire entities so @InjectRepository resolves inside KeyDirectoryService.
    TypeOrmModule.forFeature([KeyBundle, WrappedKeyVersion, WrappedKeyRecipient]),
  ],
  providers: [KeyDirectoryService, JwtAuthGuard],
  controllers: [KeyDirectoryController],
  exports: [KeyDirectoryService],
})
export class KeyDirectoryModule {}
