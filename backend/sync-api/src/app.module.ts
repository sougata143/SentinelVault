import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SyncModule } from './sync/sync.module';
import { HealthController } from './health.controller';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      url: process.env.DATABASE_URL || 'postgres://sentinel_admin:sentinel_password_change_me@localhost:5432/sentinelvault',
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: true, // TEMPORARY: Auto-create tables for initial setup. Will be replaced with migrations.
      logging: false,
      retryAttempts: 2,
    }),
    /** JWT_SECRET is the same root .env secret shared by all four backend services.
     *  auth-service signs tokens with it; sync-api verifies them with the same key. */
    JwtModule.registerAsync({
      global: true,
      useFactory: () => ({
        secret: process.env.JWT_SECRET || 'sentinelvault_jwt_secret_key_change_in_production',
        signOptions: { expiresIn: '24h' },
      }),
    }),
    SyncModule,
  ],
  controllers: [HealthController],
  providers: [],
})
export class AppModule { }
