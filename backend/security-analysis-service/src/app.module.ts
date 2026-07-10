import { Module } from '@nestjs/common';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import { SecurityAnalysisModule } from './security-analysis/security-analysis.module';
import { BreachMonitorModule } from './breach-monitor/breach-monitor.module';
import { FileReputationModule } from './file-reputation/file-reputation.module';

@Module({
  imports: [
    ThrottlerModule.forRoot([{
      ttl: 60000,
      limit: 100,
    }]),
    SecurityAnalysisModule,
    BreachMonitorModule,
    FileReputationModule,
  ],
  controllers: [],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}


