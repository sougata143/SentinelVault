---
name: phishing-url-detection
description: Use when building or modifying URL analysis features — the heuristic scanner, reputation API integration (Google Safe Browsing / PhishTank), or the AI explanation of why a URL looks suspicious.
---

# Skill: Phishing URL Detection

## Objective
Analyze a URL in three layers and return a structured verdict, without ever
needing to send full user browsing history or unrelated context anywhere.

## Layer 1 — Local heuristics (no network, run first)
Check for: punycode/homoglyph domains (e.g. `аpple.com` with Cyrillic а),
IP-literal hosts, excessive subdomain nesting, suspicious TLDs, URL shorteners
masking destination, mismatched anchor text vs. href, presence of urgency
keywords in surrounding context if available.

## Layer 2 — Reputation lookup
Query Google Safe Browsing API and/or PhishTank/URLhaus with the domain
(not with any user-identifying query params attached) for a known-bad
verdict. Cache results briefly to avoid redundant calls on repeated checks
of the same domain.

## Layer 3 — AI explanation
Send only `{domain, heuristic_flags: [...], reputation_verdict}` to the AI
insights service. Never send the full URL with query strings/tokens (which
can contain session identifiers or PII) unless explicitly stripped first.

## Rules of engagement
- Fail safe: if reputation APIs are unreachable, fall back to heuristic-only
  verdict and label it as such in the UI rather than silently passing.
- Rate-limit reputation API calls client-side to avoid quota exhaustion and
  avoid leaking a user's full browsing pattern to the third-party API in a
  burst.
- Write tests with known phishing-pattern examples (homoglyph domains,
  IP-literal URLs) and known-safe examples to check for false positives.

## Output location
`core/security/url_scanner.dart` for logic; reputation API client in
`backend/security-analysis-service/url-reputation/`.
