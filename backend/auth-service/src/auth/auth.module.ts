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
import { SessionEntity } from './entities/session.entity';
import { SsoConfigEntity } from './entities/sso-config.entity';
import { SsoService } from './sso.service';
import { PersonalAccessTokenEntity } from './entities/pat.entity';
import { PatService } from './pat.service';
import { JwtAuthGuard } from '../common/jwt-auth.guard';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      User,
      WebauthnCredential,
      AuditEventEntity,
      SessionEntity,
      SsoConfigEntity,
      PersonalAccessTokenEntity,
    ]),
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
  providers: [AuthService, UserRepository, RedisService, AuditService, SsoService, PatService, JwtAuthGuard],
  exports: [AuthService, UserRepository, JwtModule, RedisService, AuditService, SsoService, PatService, JwtAuthGuard],
})
export class AuthModule {}
