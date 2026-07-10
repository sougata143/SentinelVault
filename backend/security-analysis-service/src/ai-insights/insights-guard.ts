import { ALLOWED_KEYS, InsightsPayload } from './insights-payload';

/**
 * Thrown when an AI-insights payload is rejected because it contains raw
 * sensitive data or does not conform to the approved schema.
 *
 * This is a plain Error (not a NestJS HttpException) so the guard stays
 * decoupled from the HTTP layer and is fully testable without a running server.
 */
export class InsightsPayloadRejectedError extends Error {
  constructor(reason: string) {
    super(`InsightsPayload rejected: ${reason}`);
    this.name = 'InsightsPayloadRejectedError';
  }
}

// ── Entropy constants ─────────────────────────────────────────────────────────

/**
 * Minimum character length for a string to be checked for high entropy.
 * Short strings (e.g. 'pdf', 'pass') are never mistaken for secrets.
 */
const ENTROPY_CHECK_MIN_LEN = 20;

/**
 * Shannon entropy threshold above which a string is considered a potential
 * raw secret (API key, password, base64 blob, etc.).
 * Typical natural-language text scores 3.5–4.0; random secrets score > 4.5.
 */
const HIGH_ENTROPY_THRESHOLD = 4.5;

// ── Pattern constants ─────────────────────────────────────────────────────────

/** RFC-5321-ish email pattern — any string matching this in a payload slot
 *  that is NOT supposed to contain an email is flagged. */
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Presence of a scheme separator in a string value flags a raw URL. */
const URL_SCHEME_PATTERN = /:\/\//;

// ── Shannon entropy ───────────────────────────────────────────────────────────

/**
 * Computes the Shannon entropy of [s] in bits per character.
 *
 * H = -Σ p(c) × log₂(p(c))
 *
 * A string of purely random ASCII characters scores ~6.5 bits.
 * A typical English sentence scores ~3.5 bits.
 * The threshold of 4.5 lies safely between natural text and secrets.
 */
function shannonEntropy(s: string): number {
  const freq = new Map<string, number>();
  for (const ch of s) freq.set(ch, (freq.get(ch) ?? 0) + 1);
  let h = 0;
  for (const count of freq.values()) {
    const p = count / s.length;
    h -= p * Math.log2(p);
  }
  return h;
}

// ── Guard functions ───────────────────────────────────────────────────────────

/**
 * Checks every string value in [payload] for patterns that indicate a raw
 * secret has been accidentally included.
 *
 * Rules (applied in priority order):
 * 1. Email-address format  → reject (email addresses must never enter the LLM).
 * 2. URL scheme (`://`)    → reject (full URLs must never enter the LLM).
 * 3. High-entropy string   → reject when length ≥ 20 and entropy > 4.5 bits.
 *
 * Throws [InsightsPayloadRejectedError] on the first violation found.
 * The payload is NEVER logged when rejected — only the violation reason is.
 */
export function rejectIfRawSecret(payload: Record<string, unknown>): void {
  for (const [key, value] of Object.entries(payload)) {
    if (key === 'finding_type') continue; // discriminant key is always safe

    if (typeof value === 'string') {
      checkString(key, value);
    } else if (Array.isArray(value)) {
      for (const item of value) {
        if (typeof item === 'string') checkString(key, item);
      }
    }
  }
}

function checkString(key: string, value: string): void {
  if (EMAIL_PATTERN.test(value)) {
    throw new InsightsPayloadRejectedError(
      `Field "${key}" contains an email address — raw emails are never forwarded to the LLM.`,
    );
  }
  if (URL_SCHEME_PATTERN.test(value)) {
    throw new InsightsPayloadRejectedError(
      `Field "${key}" contains a URL scheme — full URLs must not enter the LLM prompt.`,
    );
  }
  if (value.length >= ENTROPY_CHECK_MIN_LEN) {
    const entropy = shannonEntropy(value);
    if (entropy > HIGH_ENTROPY_THRESHOLD) {
      throw new InsightsPayloadRejectedError(
        `Field "${key}" has high entropy (${entropy.toFixed(2)} bits) suggesting a raw secret. ` +
          `Only structured signals are permitted.`,
      );
    }
  }
}

/**
 * Validates [payload] against the strict allow-list for its declared
 * `finding_type`.  Any key not in the allow-list causes a rejection.
 *
 * This is a defense against future upstream modules accidentally adding
 * extra fields that might carry sensitive data.
 *
 * Throws [InsightsPayloadRejectedError] on the first extra key found.
 */
export function validateSchema(payload: InsightsPayload): void {
  const allowed = ALLOWED_KEYS[payload.finding_type];
  if (!allowed) {
    throw new InsightsPayloadRejectedError(
      `Unknown finding_type "${payload.finding_type as string}".`,
    );
  }

  for (const key of Object.keys(payload)) {
    if (!allowed.has(key)) {
      throw new InsightsPayloadRejectedError(
        `Unexpected field "${key}" in "${payload.finding_type}" payload — ` +
          `only [${[...allowed].join(', ')}] are permitted.`,
      );
    }
  }
}
