---
name: phishing-email-detection
description: Use when building or modifying email phishing analysis — header authentication checks (SPF/DKIM/DMARC), sender/reply-to spoofing detection, or extracting URLs from email bodies for the phishing-url-detection skill.
---

# Skill: Phishing Email Detection

## Objective
Analyze an email's headers and structure for phishing indicators, extract
URLs for downstream URL analysis, and produce a redacted structured summary
— never forward full email body text to third-party or AI services.

## What to check
- SPF, DKIM, DMARC pass/fail from headers.
- `From` display name vs. actual sending domain mismatch.
- `Reply-To` differing from `From` domain.
- Extract all URLs from the body/HTML and hand off to the
  `phishing-url-detection` skill's scanner for each.
- Optional: basic urgency/pressure language detection (e.g. "verify
  immediately", "account suspended") via local keyword/pattern matching, not
  by sending body text to an LLM.

## Rules of engagement
- Treat the email body as sensitive by default. Only pass extracted,
  minimal signals to the AI insights layer:
  ```json
  {
    "spf": "fail",
    "dkim": "fail",
    "sender_domain": "paypa1-secure.com",
    "display_name": "PayPal Support",
    "url_flags": ["homoglyph_domain"],
    "urgency_language_detected": true
  }
  ```
- Never include the raw body, attachments, or full header dump in any
  network call beyond what's strictly needed for local parsing.
- Redact anything matching credential-like patterns (long alphanumeric
  strings, "password:", API key formats) before any snippet — if any — is
  used elsewhere.

## Output location
`core/security/email_scanner.dart` for parsing logic. Reuses
`phishing-url-detection`'s scanner for embedded URLs — do not duplicate
that logic here.
