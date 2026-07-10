import { Module } from '@nestjs/common';
import { AiInsightsService } from './ai-insights.service';

/**
 * Shared AI-insights NestJS module.
 *
 * Import this module into any security-feature module that needs to generate
 * plain-English explanations.  The service enforces all payload guards
 * (raw-secret rejection, schema allow-list) in one place.
 */
@Module({
  providers: [AiInsightsService],
  exports: [AiInsightsService],
})
export class AiInsightsModule {}
