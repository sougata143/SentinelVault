import { Injectable } from '@nestjs/common';
import { UrlReputationService } from '../url-reputation/url-reputation.service';
import { AiInsightsService } from '../ai-insights/ai-insights.service';
import { InsightsResult } from '../ai-insights/insights-payload';

@Injectable()
export class SecurityAnalysisService {
  constructor(
    private readonly reputationService: UrlReputationService,
    private readonly aiInsights: AiInsightsService,
  ) {}

  /**
   * Scans a domain, performs reputation lookup, and returns an AI summary.
   *
   * Security Invariant: The full URL (path, query, fragment) is NEVER
   * transmitted.  Only the domain and named heuristic flags reach the AI layer.
   */
  public async scanUrl(
    domain: string,
    heuristics: string[],
  ): Promise<{
    reputationVerdict: string;
    aiInsights: InsightsResult;
    isMalicious: boolean;
  }> {
    const reputationVerdict = await this.reputationService.lookup(domain);
    const isMalicious =
      reputationVerdict === 'malicious' || heuristics.length > 0;

    // AI Insights: only domain + named flags + verdict reach the LLM.
    const aiInsights = await this.aiInsights.generateInsights({
      finding_type: 'url_scan',
      domain,
      heuristic_flags: heuristics,
      reputation_verdict: reputationVerdict,
    });

    return { reputationVerdict, aiInsights, isMalicious };
  }

  /**
   * Generates AI insights for a password strength result.
   * The raw password is NEVER accepted — only the derived score and patterns.
   */
  public async explainPasswordStrength(
    score: number,
    matchedPatterns: string[],
  ): Promise<InsightsResult> {
    return this.aiInsights.generateInsights({
      finding_type: 'password_strength',
      score,
      matched_patterns: matchedPatterns,
    });
  }

  /**
   * Generates AI insights for an email-scan header analysis.
   * Raw email content is NEVER accepted — only authentication signals.
   */
  public async explainEmailScan(signals: {
    spf_result: string;
    dkim_result: string;
    dmarc_result: string;
    sender_domain_match: boolean;
    url_flag_count: number;
  }): Promise<InsightsResult> {
    return this.aiInsights.generateInsights({
      finding_type: 'email_scan',
      ...signals,
    });
  }
}
