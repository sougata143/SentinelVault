import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BreachStore } from './breach-store';
import { BreachMonitorService } from './breach-monitor.service';
import { BreachMonitorScheduler } from './breach-monitor.scheduler';
import { BreachMonitorController } from './breach-monitor.controller';
import { AiInsightsModule } from '../ai-insights/ai-insights.module';
import { BreachOptIn } from './entities/breach-opt-in.entity';
import { BreachEntry } from './entities/breach-entry.entity';

@Module({
  imports: [
    // ScheduleModule enables the @Cron decorator on BreachMonitorScheduler.
    ScheduleModule.forRoot(),
    // Wire the two entities so @InjectRepository works inside BreachStore.
    TypeOrmModule.forFeature([BreachOptIn, BreachEntry]),
    // Shared AI insights — guards and LLM call in one place.
    AiInsightsModule,
  ],
  controllers: [BreachMonitorController],
  providers: [
    // TypeORM-backed store — keyed by opaque email hashes, stores only metadata.
    BreachStore,
    BreachMonitorService,
    BreachMonitorScheduler,
  ],
  exports: [BreachMonitorService],
})
export class BreachMonitorModule {}
