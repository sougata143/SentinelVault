---
name: password-strength-analysis
description: Use when building or modifying the password strength meter/analyzer feature — scoring passwords, generating crack-time estimates, or the AI-generated plain-English explanation of a password's weaknesses.
---

# Skill: Password Strength Analysis

## Objective
Score password strength using pattern-and-entropy analysis (zxcvbn-style),
not naive length/charset rules, and produce a structured result that a
downstream AI-insights call can turn into a plain-English explanation.

## Rules of engagement
- This runs **entirely locally, offline** — no network call needed or
  allowed for the scoring itself.
- Use an existing vetted zxcvbn port for the target language rather than
  reimplementing the pattern-matching dictionaries from scratch.
- Output a structured object, e.g.:
  ```json
  {
    "score": 2,
    "estimated_crack_time": "3 hours",
    "matched_patterns": ["common_substitution", "keyboard_sequence"],
    "suggestions": ["add an unrelated word", "avoid keyboard patterns"]
  }
  ```
- **Never** send the actual password to any network call, logging system,
  or the AI insights service. Only `matched_patterns` and `score` may be
  sent to the AI layer to generate the human-readable explanation.
- The AI-generated explanation prompt should look roughly like: "A user's
  password was flagged for: {matched_patterns}. In 2 plain sentences,
  explain why this is risky and what to do instead. Do not ask for or
  reference the actual password." — enforce this via the AI insights
  service's system prompt, not by trusting the caller.

## Output location
Core scoring logic: `core/security/password_strength.dart` (or
`.rs` if using the Rust-core variant). UI component in
`app/lib/features/password_strength/`.
