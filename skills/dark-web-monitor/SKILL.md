---
name: dark-web-monitor
description: Use when building or modifying breach/dark-web monitoring — checking saved emails and passwords against breach databases, the scheduled background check job, or the breach-notification AI summary.
---

# Skill: Dark-Web / Breach Monitor

## Objective
Periodically check user emails (and, if the user opts in, password hashes)
against known-breach databases using privacy-preserving lookups, and
generate a plain-English notification when something new turns up.

## Required approach — k-anonymity, not raw submission
- Use **Have I Been Pwned**'s range-query API pattern for both:
  - **Password checks**: hash the password with SHA-1 locally, send only
    the first 5 hex characters of the hash, and check the returned suffix
    list locally. Never send a full password or full hash.
  - **Email breach checks**: HIBP's email-breach endpoint requires the
    email itself (there's no k-anonymity variant for email lookups) — so
    this call must be explicit opt-in, clearly disclosed to the user, and
    rate-limited/scheduled (e.g. once daily), not triggered on every app
    open.
- Never send a password in any form other than the truncated SHA-1 prefix
  described above.

## Scheduled job
- Backend background worker (`backend/security-analysis-service/`) runs a
  daily job per opted-in user, diffs results against previously seen
  breaches, and only notifies on *new* findings to avoid alert fatigue.

## AI summary
- Feed the AI insights layer only: `{breach_name, breach_date,
  data_classes_exposed: [...]}` — never the user's actual email or
  password. Prompt it to explain what was exposed and recommend concrete
  next steps (rotate password, enable MFA on that service, etc.).

## Rules of engagement
- Clearly disclose in UI/UX that opting into email breach checks means the
  email address is sent to a third-party API (HIBP) — this is a
  necessary exception to the "nothing leaves the device" rule and must be
  explicit, not buried in fine print.
- Cache/store only breach metadata (name, date, data classes) needed to
  detect "new" findings — not full API responses long-term.

## Output location
`backend/security-analysis-service/breach-monitor/` for the job and API
client; UI in `app/lib/features/breach_monitor/`.
