/**
 * Strongly-typed discriminated-union payload shapes for the AI Insights layer.
 *
 * SECURITY INVARIANT: These are the ONLY shapes that may be forwarded to the
 * LLM.  Each variant contains exclusively structured signals — no raw
 * passwords, email addresses, file contents, or other sensitive values.
 *
 * The `finding_type` discriminant is used by `insights-guard.ts` to look up
 * the exact allow-list of permitted keys for each payload type.
 */

// ── Per-finding-type signal shapes ──────────────────────────────────────────

/**
 * Signals from the local password-strength scorer (zxcvbn-style).
 * The raw password is NEVER included — only the derived metrics.
 */
export interface PasswordStrengthPayload {
  readonly finding_type: 'password_strength';
  /** zxcvbn-style score 0–4. */
  readonly score: number;
  /** Human-readable pattern names that drove the score (e.g. 'dictionary'). */
  readonly matched_patterns: readonly string[];
}

/**
 * Signals from the three-layer URL / phishing scanner.
 * Only the domain (no path, query, or fragment) and heuristic flag names.
 */
export interface UrlScanPayload {
  readonly finding_type: 'url_scan';
  /** The domain portion only — never the full URL with query params. */
  readonly domain: string;
  /** Named heuristic flags that fired (e.g. 'punycode_or_homoglyph'). */
  readonly heuristic_flags: readonly string[];
  /** Verdict from the reputation layer. */
  readonly reputation_verdict: string;
}

/**
 * Signals from the email header / SPF/DKIM/DMARC scanner.
 * Raw email headers and body content are NEVER included.
 */
export interface EmailScanPayload {
  readonly finding_type: 'email_scan';
  /** SPF check result string (e.g. 'pass', 'fail', 'neutral'). */
  readonly spf_result: string;
  /** DKIM check result string. */
  readonly dkim_result: string;
  /** DMARC check result string. */
  readonly dmarc_result: string;
  /** Whether the From: domain matches the envelope sender domain. */
  readonly sender_domain_match: boolean;
  /** Number of suspicious URL flags found in the email body. */
  readonly url_flag_count: number;
}

/**
 * Signals from the HIBP breach monitor.
 * The raw email address is NEVER included — only aggregate metadata.
 */
export interface BreachMonitorPayload {
  readonly finding_type: 'breach_monitor';
  /** Total number of breaches the account appears in. */
  readonly breach_count: number;
  /** Deduplicated list of data-class strings (e.g. 'Passwords', 'Emails'). */
  readonly data_classes: readonly string[];
}

/**
 * Signals from the local file security scanner (Layer 1) plus the
 * VirusTotal hash-reputation verdict (Layer 2).
 * Raw file bytes, filenames, and full paths are NEVER included.
 */
export interface FileScanPayload {
  readonly finding_type: 'file_scan';
  /** Lowercased declared file extension (e.g. 'pdf', 'exe'). */
  readonly file_extension: string;
  /** True when magic bytes contradict the declared extension. */
  readonly signature_mismatch: boolean;
  /** True when the filename contains a dangerous double extension. */
  readonly double_extension: boolean;
  /** True when the file is a macro-enabled Office format. */
  readonly macro_detected: boolean;
  /** Verdict from the VirusTotal hash lookup ('clean'|'malicious'|'suspicious'|'unknown'). */
  readonly reputation_verdict: string;
}

/**
 * Weekly Security Digest structured signals.
 * Contains only non-sensitive aggregate stats.
 */
export interface WeeklyDigestPayload {
  readonly finding_type: 'weekly_digest';
  readonly total_passwords: number;
  readonly weak_passwords: number;
  readonly reused_passwords: number;
  readonly health_score: number;
  readonly breached_accounts: number;
}

/** Discriminated union of all approved signal shapes. */
export type InsightsPayload =
  | PasswordStrengthPayload
  | UrlScanPayload
  | EmailScanPayload
  | BreachMonitorPayload
  | FileScanPayload
  | WeeklyDigestPayload;

/** Output returned by the AI Insights service. */
export interface InsightsResult {
  /** 2–4 plain-English sentences explaining the risk. */
  readonly summary: string;
  /** Concrete numbered actions the user should take. */
  readonly recommended_actions: readonly string[];
}

// ── Allow-list: exactly which keys are permitted per finding type ─────────────
// Any key NOT in this list causes the guard to reject the payload.

export const ALLOWED_KEYS: Readonly<
  Record<InsightsPayload['finding_type'], ReadonlySet<string>>
> = {
  password_strength: new Set(['finding_type', 'score', 'matched_patterns']),
  url_scan: new Set([
    'finding_type',
    'domain',
    'heuristic_flags',
    'reputation_verdict',
  ]),
  email_scan: new Set([
    'finding_type',
    'spf_result',
    'dkim_result',
    'dmarc_result',
    'sender_domain_match',
    'url_flag_count',
  ]),
  breach_monitor: new Set(['finding_type', 'breach_count', 'data_classes']),
  file_scan: new Set([
    'finding_type',
    'file_extension',
    'signature_mismatch',
    'double_extension',
    'macro_detected',
    'reputation_verdict',
  ]),
  weekly_digest: new Set([
    'finding_type',
    'total_passwords',
    'weak_passwords',
    'reused_passwords',
    'health_score',
    'breached_accounts',
  ]),
};

// ── Static fallback summaries (returned when the LLM is unavailable) ─────────

export const FALLBACK_INSIGHTS: Readonly<
  Record<InsightsPayload['finding_type'], InsightsResult>
> = {
  password_strength: {
    summary:
      'This password has been scored for strength using pattern analysis. ' +
      'Weak passwords are the leading cause of account compromise. ' +
      'A strong password uses at least 16 characters with no recognisable words.',
    recommended_actions: [
      'Use a randomly generated password of 16+ characters.',
      'Enable two-factor authentication on this account.',
      'Store the new password in your SentinelVault vault.',
    ],
  },
  url_scan: {
    summary:
      'This URL was analysed against local heuristics and reputation data. ' +
      'Phishing sites frequently use lookalike domains or IP addresses. ' +
      'Avoid entering credentials on pages reached through unsolicited links.',
    recommended_actions: [
      'Verify the domain spelling matches the organisation you expect.',
      'Look for a valid HTTPS certificate on the destination page.',
      'Do not enter passwords or payment details if any flag was raised.',
    ],
  },
  email_scan: {
    summary:
      'The email headers were analysed for authentication failures. ' +
      'Spoofed sender addresses are the most common entry point for phishing. ' +
      'SPF, DKIM, and DMARC failures together strongly indicate a spoofed message.',
    recommended_actions: [
      'Do not click links or open attachments in this email.',
      'Contact the apparent sender via a known-good channel to verify.',
      'Report the message to your email provider as phishing.',
    ],
  },
  breach_monitor: {
    summary:
      'Your email address was found in one or more data breach datasets. ' +
      'Exposed credentials are frequently sold and used in credential-stuffing attacks. ' +
      'Any password shared with a breached service should be changed immediately.',
    recommended_actions: [
      'Change the password on every account that used the breached service.',
      'Enable two-factor authentication where possible.',
      'Check whether saved vault items share this password and update them.',
    ],
  },
  file_scan: {
    summary:
      'The file was analysed for common malware indicators. ' +
      'Signature mismatches and double extensions are hallmarks of executables disguised as documents. ' +
      'Macro-enabled Office files can execute code automatically when opened.',
    recommended_actions: [
      'Do not open this file unless you fully trust its source.',
      'Run a full antivirus scan before executing any flagged file.',
      'Submit the file to VirusTotal for a deeper analysis if still uncertain.',
    ],
  },
  weekly_digest: {
    summary:
      'Your weekly security digest shows a stable posture. ' +
      'Keep checking and updating weak or reused passwords to protect your online accounts.',
    recommended_actions: [
      'Enable two-factor authentication on all critical accounts.',
      'Replace reused passwords with generated ones.',
      'Run a dark-web check periodically.',
    ],
  },
};

