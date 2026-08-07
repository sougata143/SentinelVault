import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { UserRepository } from './user.repository';
import { RedisService } from './redis.service';
import { User } from './entities/user.entity';
import { WebauthnCredential } from './entities/webauthn-credential.entity';
import { AuditEventEntity } from './entities/audit-event.entity';
import { AuditService } from './audit.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([User, WebauthnCredential, AuditEventEntity]),
    JwtModule.registerAsync({
      /** JWT_SECRET is already present in the root .env (see RUNNING_LOCALLY.md).
       *  It is shared across all four backend services so each can verify tokens
       *  issued here without an extra secret-distribution step. */
      useFactory: () => ({
        secret: process.env.JWT_SECRET,
        signOptions: { expiresIn: '24h' },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, UserRepository, RedisService, AuditService],
  exports: [AuthService, UserRepository, JwtModule, RedisService, AuditService],
})
export class AuthModule {}
