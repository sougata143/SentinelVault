import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
} from '@nestjs/common';
import { BreachMonitorService } from './breach-monitor.service';
import { BreachEntry } from './breach-store';
import { AiInsightsService } from '../ai-insights/ai-insights.service';
import { InsightsResult } from '../ai-insights/insights-payload';

/** Request body for opting into email breach monitoring. */
interface OptInDto {
  /** Opaque SHA-256 identifier for the user's email. Used as the store key. */
  emailHash: string;
  /**
   * The plaintext email address.  Sent to HIBP only; never stored server-side.
   * The client must have shown the disclosure dialog before sending this.
   */
  email: string;
}

/** Response for a manual email breach check. */
interface BreachCheckResponse {
  emailHash: string;
  isOptedIn: boolean;
  breaches: BreachEntry[];
  newBreaches: BreachEntry[];
  /** AI-generated plain-English summary of the breach findings (if any). */
  aiInsights?: InsightsResult;
}

/**
 * REST endpoints for the opt-in email breach monitor.
 *
 * Security rules enforced here:
 * - The `email` field from [OptInDto] is passed *directly* to the service and
 *   never stored in this controller or in any log statement.
 * - All stored data (via [BreachStore]) contains only breach metadata keyed by
 *   [emailHash].
 * - AI insights receive ONLY `{ breach_count, data_classes }` — never the
 *   email address or raw HIBP response.
 */
@Controller('breach-monitor')
export class BreachMonitorController {
  constructor(
    private readonly breachMonitorService: BreachMonitorService,
    private readonly aiInsights: AiInsightsService,
  ) {}

  /**
   * Opts a user's email into daily breach monitoring.
   * The client MUST have displayed the third-party disclosure dialog and
   * received explicit user consent before calling this endpoint.
   */
  @Post('opt-in')
  @HttpCode(HttpStatus.OK)
  async optIn(@Body() dto: OptInDto): Promise<{ message: string }> {
    await this.breachMonitorService.optIn(dto.emailHash, dto.email);
    return { message: 'Email monitoring enabled.' };
  }

  /**
   * Removes an email hash from breach monitoring and purges stored metadata.
   */
  @Delete('opt-out/:emailHash')
  @HttpCode(HttpStatus.OK)
  async optOut(
    @Param('emailHash') emailHash: string,
  ): Promise<{ message: string }> {
    await this.breachMonitorService.optOut(emailHash);
    return { message: 'Email monitoring disabled and data cleared.' };
  }

  /**
   * Returns stored breach metadata for the given email hash.
   * Does not trigger a fresh HIBP lookup — use /check for that.
   */
  @Get('status/:emailHash')
  async getStatus(
    @Param('emailHash') emailHash: string,
  ): Promise<{ isOptedIn: boolean; breaches: BreachEntry[] }> {
    return {
      isOptedIn: await this.breachMonitorService.isOptedIn(emailHash),
      breaches: await this.breachMonitorService.getStoredBreaches(emailHash),
    };
  }

  /**
   * Triggers an immediate HIBP check for the given email hash and returns
   * any newly discovered breaches, plus an AI-insights summary.
   *
   * AI signal: only `{ breach_count, data_classes }` — email address is
   * never forwarded to the AI layer.
   */
  @Post('check')
  @HttpCode(HttpStatus.OK)
  async check(
    @Body() body: { emailHash: string },
  ): Promise<BreachCheckResponse> {
    const newBreaches = await this.breachMonitorService.runCheckAndDiff(
      body.emailHash,
    );
    const allBreaches = await this.breachMonitorService.getStoredBreaches(body.emailHash);

    // Generate AI insights only when there are breaches to explain.
    let aiInsights: InsightsResult | undefined;
    if (allBreaches.length > 0) {
      // Collect all unique data classes across every breach — no email address.
      const dataClasses = [
        ...new Set(allBreaches.flatMap((b) => b.dataClasses)),
      ];
      aiInsights = await this.aiInsights.generateInsights({
        finding_type: 'breach_monitor',
        breach_count: allBreaches.length,
        data_classes: dataClasses,
      });
    }

    return {
      emailHash: body.emailHash,
      isOptedIn: await this.breachMonitorService.isOptedIn(body.emailHash),
      breaches: allBreaches,
      newBreaches,
      ...(aiInsights ? { aiInsights } : {}),
    };
  }
}
