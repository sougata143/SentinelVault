// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Sharing Service – Root Module
// ─────────────────────────────────────────────────────────────────────────────
import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';
import { TypeOrmModule } from '@nestjs/typeorm';
import { KeyDirectoryModule } from './key-directory/key-directory.module';
import { ShareInviteModule } from './share-invite/share-invite.module';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      url: process.env.DATABASE_URL,
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: true, // TEMPORARY: Auto-create tables for initial setup. Will be replaced with migrations.
      logging: false,
    }),
    // Rate-limit: 60 requests per 60 s per IP to prevent key enumeration
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    KeyDirectoryModule,
    ShareInviteModule,
  ],
})
export class SharingModule { }
