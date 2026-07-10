import { Module } from '@nestjs/common';
import { SecurityAnalysisController } from './security-analysis.controller';
import { SecurityAnalysisService } from './security-analysis.service';
import { UrlReputationService } from '../url-reputation/url-reputation.service';
import { AiInsightsModule } from '../ai-insights/ai-insights.module';

@Module({
  imports: [AiInsightsModule],
  controllers: [SecurityAnalysisController],
  providers: [SecurityAnalysisService, UrlReputationService],
  exports: [SecurityAnalysisService, UrlReputationService],
})
export class SecurityAnalysisModule {}

