import {
  Controller,
  Post,
  Body,
  HttpCode,
  HttpStatus,
  BadRequestException,
} from '@nestjs/common';
import { SecurityAnalysisService } from './security-analysis.service';
import { InsightsPayload, InsightsResult } from '../ai-insights/insights-payload';
import { InsightsPayloadRejectedError } from '../ai-insights/insights-guard';
import { AiInsightsService } from '../ai-insights/ai-insights.service';

@Controller('security-analysis')
export class SecurityAnalysisController {
  constructor(
    private readonly securityService: SecurityAnalysisService,
    private readonly aiInsights: AiInsightsService,
  ) {}

  @Post('scan-url')
  @HttpCode(HttpStatus.OK)
  public async scanUrl(
    @Body() body: { domain?: string; heuristics?: string[] },
  ) {
    const { domain, heuristics } = body;
    if (!domain) {
      throw new BadRequestException('domain parameter is required');
    }
    return this.securityService.scanUrl(domain, heuristics ?? []);
  }

  /**
   * Generic AI-insights endpoint for client-side modules that don't have
   * their own controller (password_strength and email_scan).
   *
   * Accepts any approved InsightsPayload shape.  The guard + schema
   * validation in AiInsightsService will reject anything malformed.
   */
  @Post('insights')
  @HttpCode(HttpStatus.OK)
  public async insights(
    @Body() payload: InsightsPayload,
  ): Promise<InsightsResult> {
    try {
      return await this.aiInsights.generateInsights(payload);
    } catch (err) {
      if (err instanceof InsightsPayloadRejectedError) {
        throw new BadRequestException(err.message);
      }
      throw err;
    }
  }
}
