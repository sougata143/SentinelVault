---
name: ai-insights-generator
description: Use when building or modifying the shared AI-insights service that turns structured security findings (from password/URL/email/file/breach modules) into plain-English explanations. Load this whenever wiring a new module's output to the LLM call.
---

# Skill: AI Insights Generator

## Objective
One shared backend service that all security modules call through, so the
"never send raw sensitive data to the LLM" rule is enforced in a single
place rather than reimplemented per module.

## Interface
Input: a small, typed, structured JSON object per finding type (see each
module's own SKILL.md for its exact shape — e.g. `matched_patterns` for
passwords, `{spf, dkim, sender_domain, url_flags}` for email).
Output: `{summary: string, recommended_actions: string[]}`.

## System prompt requirements for the LLM call
The system prompt given to the LLM must instruct it to:
1. Explain the risk in 2–4 plain sentences, no jargon without a one-line
   definition.
2. Give concrete, numbered next steps.
3. Never ask the caller to provide the original sensitive value (password,
   full email, file) — it should only ever reason over the structured
   signals it was given.
4. Refuse/flag gracefully if the input object contains anything that looks
   like a raw secret (long high-entropy string, email address format,
   etc.) rather than expected structured fields — this is a safety net in
   case an upstream module has a bug and leaks something it shouldn't.

## Rules of engagement
- This service must validate incoming payloads against a strict schema per
  finding type and reject anything with unexpected extra fields (defense
  against a future module accidentally passing raw data through).
- Log only the structured input and the generated summary — never
  intermediate prompts if they could theoretically be modified to include
  more; keep the full prompt template in code, not in logs.
- Set a short retention window on any logs of this service's traffic.

## Output location
`backend/security-analysis-service/ai-insights/` — a single shared module
imported by the password/URL/email/file/breach modules, not duplicated.
