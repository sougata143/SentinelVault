/**
 * Unit tests for the AI Insights guard and service.
 *
 * These tests run WITHOUT a running NestJS server and WITHOUT a live LLM.
 * They verify that:
 *   - Approved payloads pass all guards.
 *   - Malformed payloads (raw secrets, unknown fields) are rejected BEFORE
 *     any data reaches the LLM call path.
 *   - The service returns a valid InsightsResult shape on success.
 *   - The static fallback is returned when no GEMINI_API_KEY is set.
 */

import {
  InsightsPayloadRejectedError,
  rejectIfRawSecret,
  validateSchema,
} from './insights-guard';
import { AiInsightsService } from './ai-insights.service';
import {
  BreachMonitorPayload,
  EmailScanPayload,
  FileScanPayload,
  InsightsPayload,
  PasswordStrengthPayload,
  UrlScanPayload,
  FALLBACK_INSIGHTS,
} from './insights-payload';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeService(): AiInsightsService {
  // Construct directly — no NestJS DI needed for pure unit tests.
  return new AiInsightsService();
}

// ── Valid fixture payloads ────────────────────────────────────────────────────

const validPasswordPayload: PasswordStrengthPayload = {
  finding_type: 'password_strength',
  score: 1,
  matched_patterns: ['dictionary', 'l33t_substitution'],
};

const validUrlPayload: UrlScanPayload = {
  finding_type: 'url_scan',
  domain: 'suspicious-login.co.uk',
  heuristic_flags: ['excessive_subdomains', 'suspicious_tld'],
  reputation_verdict: 'unknown',
};

const validEmailPayload: EmailScanPayload = {
  finding_type: 'email_scan',
  spf_result: 'fail',
  dkim_result: 'none',
  dmarc_result: 'fail',
  sender_domain_match: false,
  url_flag_count: 3,
};

const validBreachPayload: BreachMonitorPayload = {
  finding_type: 'breach_monitor',
  breach_count: 2,
  data_classes: ['Passwords', 'Email addresses'],
};

const validFilePayload: FileScanPayload = {
  finding_type: 'file_scan',
  file_extension: 'pdf',
  signature_mismatch: true,
  double_extension: false,
  macro_detected: false,
  reputation_verdict: 'malicious',
};

// ── Guard tests ───────────────────────────────────────────────────────────────

describe('rejectIfRawSecret', () => {
  test('1. Valid password_strength payload passes without throwing', () => {
    expect(() =>
      rejectIfRawSecret(validPasswordPayload as unknown as Record<string, unknown>),
    ).not.toThrow();
  });

  test('2. Valid url_scan payload passes without throwing', () => {
    expect(() =>
      rejectIfRawSecret(validUrlPayload as unknown as Record<string, unknown>),
    ).not.toThrow();
  });

  test('3. Valid file_scan payload passes without throwing', () => {
    expect(() =>
      rejectIfRawSecret(validFilePayload as unknown as Record<string, unknown>),
    ).not.toThrow();
  });

  test('4. Payload containing a high-entropy string is rejected', () => {
    // This simulates a bug where an upstream module accidentally leaks a
    // raw password or API key into a signal slot.
    const malformedPayload = {
      finding_type: 'password_strength',
      score: 2,
      // A high-entropy string ≥ 20 chars that looks like a real secret:
      matched_patterns: ['P@ssw0rd!Xk9#mLqR7$vZ2&nY'],
    };

    expect(() =>
      rejectIfRawSecret(malformedPayload as unknown as Record<string, unknown>),
    ).toThrow(InsightsPayloadRejectedError);
  });

  test('5. Payload with an email-address string in a signal slot is rejected', () => {
    const malformedPayload = {
      finding_type: 'breach_monitor',
      // An email address must NEVER appear in the LLM payload.
      breach_count: 1,
      data_classes: ['user@example.com'],
    };

    expect(() =>
      rejectIfRawSecret(malformedPayload as unknown as Record<string, unknown>),
    ).toThrow(InsightsPayloadRejectedError);
  });

  test('6. Payload with a URL (contains "://") in a signal slot is rejected', () => {
    const malformedPayload = {
      finding_type: 'url_scan',
      domain: 'safe.example.com',
      heuristic_flags: [],
      // A full URL accidentally forwarded would expose path/query data.
      reputation_verdict: 'https://api.example.com/verdict?token=abc',
    };

    expect(() =>
      rejectIfRawSecret(malformedPayload as unknown as Record<string, unknown>),
    ).toThrow(InsightsPayloadRejectedError);
  });

  test('7. Short low-entropy strings in array fields do NOT trigger rejection', () => {
    // Pattern names like 'dictionary' or 'l33t' must not cause false positives.
    expect(() =>
      rejectIfRawSecret({
        finding_type: 'password_strength',
        score: 0,
        matched_patterns: ['dictionary', 'dates', 'keyboard_walk'],
      } as unknown as Record<string, unknown>),
    ).not.toThrow();
  });

  test('8. Rejection message is informative but does NOT include the payload value', () => {
    const secret = 'P@ssw0rd!Xk9#mLqR7$vZ2&nY';
    const malformed = {
      finding_type: 'password_strength',
      score: 1,
      matched_patterns: [secret],
    };

    let caught: Error | null = null;
    try {
      rejectIfRawSecret(malformed as unknown as Record<string, unknown>);
    } catch (e) {
      caught = e as Error;
    }

    expect(caught).toBeInstanceOf(InsightsPayloadRejectedError);
    // The error message must NOT contain the raw secret value.
    expect(caught!.message).not.toContain(secret);
  });
});

describe('validateSchema', () => {
  test('9. Valid email_scan payload passes schema validation', () => {
    expect(() => validateSchema(validEmailPayload)).not.toThrow();
  });

  test('10. Valid breach_monitor payload passes schema validation', () => {
    expect(() => validateSchema(validBreachPayload)).not.toThrow();
  });

  test('11. Payload with an unknown extra field is rejected', () => {
    // Simulates a future upstream module accidentally adding a raw field.
    const withExtraField = {
      ...validFilePayload,
      raw_file_path: '/home/user/secret_docs/invoice.pdf',
    } as unknown as InsightsPayload;

    expect(() => validateSchema(withExtraField)).toThrow(
      InsightsPayloadRejectedError,
    );
  });

  test('12. Payload with multiple unknown fields rejects on the first one', () => {
    const withExtras = {
      ...validPasswordPayload,
      raw_password: 'hunter2',
      user_email: 'alice@example.com',
    } as unknown as InsightsPayload;

    expect(() => validateSchema(withExtras)).toThrow(
      InsightsPayloadRejectedError,
    );
  });
});

// ── Service integration tests (no network) ────────────────────────────────────

describe('AiInsightsService', () => {
  beforeEach(() => {
    // Ensure no GEMINI_API_KEY is set so tests use the static fallback path.
    delete process.env.GEMINI_API_KEY;
  });

  test('13. generateInsights returns a valid InsightsResult for a clean payload', async () => {
    const service = makeService();
    const result = await service.generateInsights(validUrlPayload);

    expect(typeof result.summary).toBe('string');
    expect(result.summary.length).toBeGreaterThan(0);
    expect(Array.isArray(result.recommended_actions)).toBe(true);
    expect(result.recommended_actions.length).toBeGreaterThan(0);
  });

  test('14. generateInsights returns the static fallback when no API key is set', async () => {
    const service = makeService();
    const result = await service.generateInsights(validBreachPayload);
    const fallback = FALLBACK_INSIGHTS['breach_monitor'];

    expect(result.summary).toBe(fallback.summary);
    expect(result.recommended_actions).toEqual(fallback.recommended_actions);
  });

  test('15. generateInsights throws InsightsPayloadRejectedError for a raw-secret payload', async () => {
    const service = makeService();
    const badPayload: InsightsPayload = {
      finding_type: 'password_strength',
      score: 2,
      matched_patterns: ['P@ssw0rd!Xk9#mLqR7$vZ2&nY'], // high entropy
    };

    await expect(service.generateInsights(badPayload)).rejects.toThrow(
      InsightsPayloadRejectedError,
    );
  });

  test('16. generateInsights throws InsightsPayloadRejectedError for an extra-field payload', async () => {
    const service = makeService();
    const badPayload = {
      ...validFilePayload,
      full_file_path: '/tmp/malware.exe',
    } as unknown as InsightsPayload;

    await expect(service.generateInsights(badPayload)).rejects.toThrow(
      InsightsPayloadRejectedError,
    );
  });

  test('17. All five finding types return a valid InsightsResult via the fallback', async () => {
    const service = makeService();
    const payloads: InsightsPayload[] = [
      validPasswordPayload,
      validUrlPayload,
      validEmailPayload,
      validBreachPayload,
      validFilePayload,
    ];

    for (const payload of payloads) {
      const result = await service.generateInsights(payload);
      expect(typeof result.summary).toBe('string');
      expect(result.summary.length).toBeGreaterThan(0);
      expect(result.recommended_actions.length).toBeGreaterThan(0);
    }
  });
});
