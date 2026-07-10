import { Injectable, Logger } from '@nestjs/common';
import axios from 'axios';
import {
  FALLBACK_INSIGHTS,
  InsightsPayload,
  InsightsResult,
} from './insights-payload';
import {
  InsightsPayloadRejectedError,
  rejectIfRawSecret,
  validateSchema,
} from './insights-guard';

// ── System prompt templates (hardcoded in code — never logged) ────────────────

const SYSTEM_PROMPTS: Readonly<
  Record<InsightsPayload['finding_type'], string>
> = {
  password_strength: `You are a security education assistant embedded in a password manager.
You receive structured signals about a password's strength score and matched patterns.
Rules you MUST follow:
1. Explain the risk in 2–4 plain sentences. Define any jargon on first use.
2. Give 2–3 concrete, numbered next steps the user can take right now.
3. Never ask the user to reveal or re-enter their password.
4. Never include the original password in your response — you have not been given it.
5. Base your response ONLY on the structured signals provided.
Respond with a JSON object: {"summary":"...","recommended_actions":["step 1","step 2",...]}`,

  url_scan: `You are a security education assistant in a phishing-detection tool.
You receive structured signals: a domain name, named heuristic flags, and a reputation verdict.
Rules you MUST follow:
1. Explain the risk in 2–4 plain sentences. Define any jargon on first use.
2. Give 2–3 concrete, numbered next steps the user can take.
3. Never suggest the user visit the flagged URL to verify it.
4. Base your response ONLY on the domain and signal flags provided — do not invent details.
5. If no flags fired and reputation is clean, reassure the user clearly.
Respond with a JSON object: {"summary":"...","recommended_actions":["step 1","step 2",...]}`,

  email_scan: `You are a security education assistant in an email-safety checker.
You receive structured header-analysis signals: SPF, DKIM, DMARC results and a URL-flag count.
Rules you MUST follow:
1. Explain the risk in 2–4 plain sentences. Define any jargon on first use.
2. Give 2–3 concrete, numbered next steps.
3. Never ask the user to forward or share the email with you.
4. Do not speculate about the sender's identity beyond what the signals indicate.
5. Base your response ONLY on the authentication signals provided.
Respond with a JSON object: {"summary":"...","recommended_actions":["step 1","step 2",...]}`,

  breach_monitor: `You are a security education assistant in a data-breach notification tool.
You receive structured breach metadata: a count of breaches and a list of exposed data classes.
Rules you MUST follow:
1. Explain the risk in 2–4 plain sentences. Define any jargon on first use.
2. Give 2–3 concrete, numbered next steps prioritised by urgency.
3. Never ask the user for their email address or passwords.
4. Base your response ONLY on the breach count and data-class list provided.
Respond with a JSON object: {"summary":"...","recommended_actions":["step 1","step 2",...]}`,

  file_scan: `You are a security education assistant in a file-safety scanner.
You receive structured signals: the file extension, boolean flags for signature mismatch /
double extension / macro detection, and a VirusTotal reputation verdict.
Rules you MUST follow:
1. Explain the risk in 2–4 plain sentences. Define any jargon on first use.
2. Give 2–3 concrete, numbered next steps.
3. Never ask the user to open or execute the flagged file.
4. Do not claim certainty about whether the file is malicious — describe the risk signals.
5. Base your response ONLY on the structured flags provided.
Respond with a JSON object: {"summary":"...","recommended_actions":["step 1","step 2",...]}`,

  weekly_digest: `You are a security education assistant.
You receive structured weekly statistics about a user's password manager vault health (total passwords, weak passwords, reused passwords, health score, breached accounts).
Rules you MUST follow:
1. Explain the overall health and security risks in 2–4 plain sentences. Define any jargon on first use.
2. Give 2–3 concrete, numbered next steps.
3. Never ask the user to reveal or send their master password.
4. Base your response ONLY on the aggregate statistics provided.
Respond with a JSON object: {"summary":"...","recommended_actions":["step 1","step 2",...]}`,
};


// ── Service ───────────────────────────────────────────────────────────────────

/**
 * Shared AI-insights service used by every security module.
 *
 * ## Security invariants:
 * - [rejectIfRawSecret] and [validateSchema] always run before any LLM call.
 * - The full prompt template lives in this file, never in env vars or logs.
 * - Only `{ finding_type, success, latency_ms }` is ever written to the log.
 * - On LLM failure the service returns a static fallback — errors are never
 *   propagated in a form that could expose the prompt.
 */
@Injectable()
export class AiInsightsService {
  private readonly logger = new Logger(AiInsightsService.name);

  /**
   * Generates a plain-English security summary for [payload].
   *
   * Steps (in order — none may be skipped):
   * 1. Run [rejectIfRawSecret] — rejects before any logging.
   * 2. Run [validateSchema] — allow-list enforcement.
   * 3. Build the user message from [payload].
   * 4. Call the Gemini LLM with the hardcoded system prompt.
   * 5. Parse the JSON response into [InsightsResult].
   * 6. On any failure → return the static [FALLBACK_INSIGHTS].
   *
   * @throws [InsightsPayloadRejectedError] — caller must handle and return 400.
   */
  async generateInsights(payload: InsightsPayload): Promise<InsightsResult> {
    // ── Step 1: Raw-secret guard (runs before any logging) ─────────────────
    rejectIfRawSecret(payload as unknown as Record<string, unknown>);

    // ── Step 2: Schema allow-list validation ────────────────────────────────
    validateSchema(payload);

    const start = Date.now();
    const findingType = payload.finding_type;

    // ── Step 3: Build the structured user message ───────────────────────────
    // Omit finding_type from the user message — it's already encoded in the
    // system prompt selection.
    const { finding_type: _ft, ...signals } = payload as unknown as Record<string, unknown>;
    const userMessage = JSON.stringify(signals, null, 2);

    // ── Step 4: LLM call ────────────────────────────────────────────────────
    const geminiKey = process.env.GEMINI_API_KEY;
    if (geminiKey) {
      try {
        const result = await this.callGemini(
          geminiKey,
          SYSTEM_PROMPTS[findingType],
          userMessage,
        );
        const latency = Date.now() - start;
        // Only log the finding type + outcome — never the prompt or payload.
        this.logger.log(
          `AI insights generated | finding_type=${findingType} success=true latency_ms=${latency}`,
        );
        return result;
      } catch (err) {
        const latency = Date.now() - start;
        this.logger.warn(
          `AI insights fallback | finding_type=${findingType} success=false latency_ms=${latency}`,
        );
        // Fall through to static fallback.
      }
    } else {
      this.logger.debug(
        `GEMINI_API_KEY not set — returning static fallback for ${findingType}`,
      );
    }

    // ── Step 5: Static fallback ─────────────────────────────────────────────
    return FALLBACK_INSIGHTS[findingType];
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  private async callGemini(
    apiKey: string,
    systemPrompt: string,
    userMessage: string,
  ): Promise<InsightsResult> {
    const response = await axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`,
      {
        // Gemini 1.5 Flash supports a system instruction field.
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents: [{ parts: [{ text: userMessage }] }],
        generationConfig: {
          responseMimeType: 'application/json',
          temperature: 0.2,
          maxOutputTokens: 512,
        },
      },
      { timeout: 5000 },
    );

    const rawText: string =
      response.data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

    return this.parseResponse(rawText);
  }

  private parseResponse(rawText: string): InsightsResult {
    try {
      // Gemini may wrap JSON in a markdown code fence — strip it.
      const cleaned = rawText
        .replace(/^```json\s*/i, '')
        .replace(/```\s*$/, '')
        .trim();
      const parsed = JSON.parse(cleaned) as {
        summary?: unknown;
        recommended_actions?: unknown;
      };

      const summary =
        typeof parsed.summary === 'string' && parsed.summary.length > 0
          ? parsed.summary
          : null;

      const actions = Array.isArray(parsed.recommended_actions)
        ? (parsed.recommended_actions as unknown[])
            .filter((a): a is string => typeof a === 'string')
        : null;

      if (!summary || !actions || actions.length === 0) {
        throw new Error('Incomplete LLM response shape.');
      }

      return { summary, recommended_actions: actions };
    } catch {
      throw new Error(`Failed to parse LLM JSON response: ${rawText}`);
    }
  }
}
