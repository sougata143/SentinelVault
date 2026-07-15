import { Module } from '@nestjs/common';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SecurityAnalysisModule } from './security-analysis/security-analysis.module';
import { BreachMonitorModule } from './breach-monitor/breach-monitor.module';
import { FileReputationModule } from './file-reputation/file-reputation.module';
import { HealthController } from './health.controller';
import { JwtModule } from '@nestjs/jwt';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      url: process.env.DATABASE_URL,
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: true, // TEMPORARY: Auto-create tables for initial setup. Will be replaced with migrations.
      logging: false,
    }),
    ThrottlerModule.forRoot([{
      ttl: 60000,
      limit: 100,
    }]),
    /** JWT_SECRET is the shared root .env secret — same key auth-service signs with. */
    JwtModule.registerAsync({
      global: true,
      useFactory: () => ({
        secret: process.env.JWT_SECRET,
        signOptions: { expiresIn: '24h' },
      }),
    }),
    SecurityAnalysisModule,
    BreachMonitorModule,
    FileReputationModule,
  ],
  controllers: [HealthController],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule { }


