// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Sharing Service – Root Module
// ─────────────────────────────────────────────────────────────────────────────
import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';
import { KeyDirectoryModule } from './key-directory/key-directory.module';
import { ShareInviteModule } from './share-invite/share-invite.module';

@Module({
  imports: [
    // Rate-limit: 60 requests per 60 s per IP to prevent key enumeration
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    KeyDirectoryModule,
    ShareInviteModule,
  ],
})
export class SharingModule {}
