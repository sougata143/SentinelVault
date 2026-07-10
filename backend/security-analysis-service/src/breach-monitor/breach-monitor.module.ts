import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { BreachStore } from './breach-store';
import { BreachMonitorService } from './breach-monitor.service';
import { BreachMonitorScheduler } from './breach-monitor.scheduler';
import { BreachMonitorController } from './breach-monitor.controller';
import { AiInsightsModule } from '../ai-insights/ai-insights.module';

@Module({
  imports: [
    // ScheduleModule enables the @Cron decorator on BreachMonitorScheduler.
    ScheduleModule.forRoot(),
    // Shared AI insights — guards and LLM call in one place.
    AiInsightsModule,
  ],
  controllers: [BreachMonitorController],
  providers: [
    // Singleton store — keyed by opaque email hashes, stores only metadata.
    BreachStore,
    BreachMonitorService,
    BreachMonitorScheduler,
  ],
  exports: [BreachMonitorService],
})
export class BreachMonitorModule {}

